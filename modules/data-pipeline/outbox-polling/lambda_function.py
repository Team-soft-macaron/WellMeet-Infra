"""
Outbox 테이블을 폴링하여 처리되지 않은 메시지를 SQS로 전송하는 Lambda 함수
EventBridge에서 1시간마다 호출되어 실행
"""
import json
import boto3
import os
import pymysql
from datetime import datetime

# AWS 클라이언트 초기화
sqs_client = boto3.client("sqs", region_name='ap-northeast-2')

# 환경변수
OUTBOX_QUEUE_URL = os.environ.get("OUTBOX_QUEUE_URL")

def get_restaurant_db_connection():
    """restaurant 데이터베이스 연결을 생성합니다. (MySQL)"""
    return pymysql.connect(
        host=os.environ.get("RESTAURANT_DB_HOST"),
        user=os.environ.get("RESTAURANT_DB_USER"),
        password=os.environ.get("RESTAURANT_DB_PASSWORD"),
        database=os.environ.get("RESTAURANT_DB_NAME"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
    )

def get_unprocessed_outbox_messages():
    """처리되지 않은 outbox 메시지들을 조회합니다."""
    connection = None
    cursor = None
    
    try:
        connection = get_restaurant_db_connection()
        cursor = connection.cursor()
        
        # is_processed = 0인 메시지들을 조회
        select_query = """
            SELECT id, restaurant_id, payload, created_at 
            FROM outbox 
            WHERE is_processed = 0 
            ORDER BY created_at ASC
        """
        
        cursor.execute(select_query)
        messages = cursor.fetchall()
        
        print(f"Found {len(messages)} unprocessed outbox messages")
        return messages
        
    except Exception as e:
        print(f"Database error: {str(e)}")
        raise e
    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()

def mark_outbox_as_processed(message_id):
    """outbox 메시지를 처리 완료로 표시합니다."""
    connection = None
    cursor = None
    
    try:
        connection = get_restaurant_db_connection()
        cursor = connection.cursor()
        
        update_query = """
            UPDATE outbox 
            SET is_processed = 1 
            WHERE id = %s
        """
        
        cursor.execute(update_query, (message_id,))
        connection.commit()
        
        print(f"Marked outbox message {message_id} as processed")
        
    except Exception as e:
        print(f"Error marking outbox as processed: {str(e)}")
        if connection:
            connection.rollback()
        raise e
    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()

def send_to_outbox_queue(payload, restaurant_id):
    """SQS 큐로 메시지를 전송합니다."""
    try:
        message_body = {
            "s3Key": payload,
            "restaurantId": restaurant_id        }
        
        response = sqs_client.send_message(
            QueueUrl=OUTBOX_QUEUE_URL,
            MessageBody=json.dumps(message_body)
        )
        
        print(f"Successfully sent message to outbox queue: {response['MessageId']}")
        return True
        
    except Exception as e:
        print(f"Error sending message to SQS: {str(e)}")
        return False

def handler(event, context):
    """
    EventBridge에서 1시간마다 호출되어 outbox 테이블을 폴링하고
    처리되지 않은 메시지를 SQS로 전송
    """
    print("Starting outbox polling process...")
    
    processed_count = 0
    error_count = 0
    
    try:
        # 처리되지 않은 outbox 메시지 조회
        unprocessed_messages = get_unprocessed_outbox_messages()
        
        for message in unprocessed_messages:
            try:
                message_id = message['id']
                restaurant_id = message['restaurant_id']
                payload = message['payload']
                
                print(f"Processing outbox message: {message_id}, payload: {payload}")
                
                # SQS로 메시지 전송
                if send_to_outbox_queue(payload, restaurant_id):
                    # 전송 성공 시 outbox를 처리 완료로 표시
                    mark_outbox_as_processed(message_id)
                    processed_count += 1
                else:
                    error_count += 1
                    
            except Exception as e:
                print(f"Error processing message {message.get('id', 'unknown')}: {str(e)}")
                error_count += 1
                continue
        
        print(f"Outbox polling completed. Processed: {processed_count}, Errors: {error_count}")
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Outbox polling completed successfully",
                "processedCount": processed_count,
                "errorCount": error_count
            })
        }
        
    except Exception as e:
        print(f"Fatal error in outbox polling: {str(e)}")
        return {
            "statusCode": 500,
            "body": json.dumps({
                "message": "Outbox polling failed",
                "error": str(e)
            })
        }

if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {}
    
    # 테스트를 위한 환경 변수 설정
    os.environ["OUTBOX_QUEUE_URL"] = "https://sqs.ap-northeast-2.amazonaws.com/123456789012/test-queue"
    os.environ["RESTAURANT_DB_HOST"] = "localhost"
    os.environ["RESTAURANT_DB_USER"] = "root"
    os.environ["RESTAURANT_DB_PASSWORD"] = "password"
    os.environ["RESTAURANT_DB_NAME"] = "wellmeet"
    
    handler(test_event, None)
