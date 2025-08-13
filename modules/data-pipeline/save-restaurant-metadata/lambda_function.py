"""
식당 메타데이터를 DB에 저장하는 Lambda 함수
SQS에서 S3 key를 받아서 S3에서 데이터를 조회한 후 식당 DB에 저장
"""
import json
import boto3
import os
import pymysql
from urllib.parse import unquote_plus
import uuid

# AWS 클라이언트 초기화
s3_client = boto3.client("s3", region_name='ap-northeast-2')

# 환경변수
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME")
EMBEDDING_BUCKET_DIRECTORY = os.environ.get("EMBEDDING_BUCKET_DIRECTORY")

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

def save_restaurant_to_db(restaurant_data):
    """식당 데이터를 DB에 저장합니다."""
    connection = None
    cursor = None
    saved_count = 0

    try:
        connection = get_restaurant_db_connection()
        cursor = connection.cursor()

        # 각 restaurant마다 새로운 UUID 생성
        restaurant_id = str(uuid.uuid4())

        place_id = restaurant_data.get("placeId")
        name = restaurant_data.get("name")
        address = restaurant_data.get("address")
        latitude = restaurant_data.get("latitude") or 0.0
        longitude = restaurant_data.get("longitude") or 0.0
        thumbnail = restaurant_data.get("thumbnail") or ""

        # Restaurant DB에 저장 (MySQL)
        restaurant_insert_query = """
            INSERT INTO restaurant (
                id, name, address, latitude, longitude, thumbnail, owner_id
            ) VALUES (%s, %s, %s, %s, %s, %s, %s)
        """

        cursor.execute(
            restaurant_insert_query,
            (
                restaurant_id,
                name,
                address,
                latitude,
                longitude,
                thumbnail,
                1
            ),
        )

        saved_count += 1
        print(f"Successfully saved restaurant {place_id} to database")

        # 변경사항 커밋
        connection.commit()

    except Exception as e:
        print(f"Database error: {str(e)}")
        if connection:
            connection.rollback()
        raise e

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()

    return saved_count

def get_restaurant_data_from_s3(s3_key):
    """S3에서 식당 데이터를 읽어옵니다."""
    try:
        key = f"{EMBEDDING_BUCKET_DIRECTORY}/{s3_key}"
        print(f"Reading from S3: {S3_BUCKET_NAME}/{key}")
        
        response = s3_client.get_object(Bucket=S3_BUCKET_NAME, Key=key)
        data = json.loads(response["Body"].read().decode("utf-8"))
        
        print(f"Successfully read data from S3: {s3_key}")
        return data
        
    except Exception as e:
        print(f"Error reading from S3: {str(e)}")
        raise e

def handler(event, context):
    """
    SQS에서 S3 key를 받아서 S3에서 데이터를 조회한 후 식당 DB에 저장
    Input: SQS 메시지 {"s3Key": "embedding/xxx_embedding.json"}
    """
    print("Starting restaurant metadata save process...")
    
    saved_count = 0
    
    # SQS 메시지 처리
    for record in event.get('Records', []):
        try:
            message_body = json.loads(record['body'])
            s3_key = message_body.get('s3Key')
            
            print(f"Processing message for S3 key: {s3_key}")
            
            if not s3_key:
                print("No S3 key found in message, skipping...")
                continue
            
            # S3에서 임베딩 데이터 읽기
            embedding_data = get_restaurant_data_from_s3(s3_key)
            
            # 식당 메타데이터 추출 (reviews 제외)
            restaurant_metadata = {
                "placeId": embedding_data.get("placeId"),
                "name": embedding_data.get("name"),
                "category": embedding_data.get("category"),
                "page": embedding_data.get("page"),
                "origin_address": embedding_data.get("origin_address"),
                "address": embedding_data.get("address"),
                "latitude": embedding_data.get("latitude"),
                "longitude": embedding_data.get("longitude")
            }
            
            # placeId가 있는 경우만 DB에 저장
            if restaurant_metadata["placeId"]:
                count = save_restaurant_to_db(restaurant_metadata)
                saved_count += count
                
                print(f"Successfully processed placeId: {restaurant_metadata['placeId']}")
            else:
                print(f"No placeId found in data for key: {s3_key}")
                
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            # 개별 레코드 오류는 로그만 남기고 계속 진행
            continue
    
    print(f"Processing completed. Total saved: {saved_count}")
    
    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Restaurant metadata save completed successfully",
            "savedCount": saved_count
        })
    }

if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {
        "Records": [
            {
                "body": json.dumps({
                    "s3Key": "embedding/test_embedding.json"
                })
            }
        ]
    }

    # 테스트를 위한 환경 변수 설정
    os.environ["S3_BUCKET_NAME"] = "test-bucket"
    os.environ["EMBEDDING_BUCKET_DIRECTORY"] = "embedding"
    os.environ["RESTAURANT_DB_HOST"] = "localhost"
    os.environ["RESTAURANT_DB_USER"] = "root"
    os.environ["RESTAURANT_DB_PASSWORD"] = "password"
    os.environ["RESTAURANT_DB_NAME"] = "wellmeet"

    handler(test_event, None)
