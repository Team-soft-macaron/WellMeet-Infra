"""
Vector DB에 벡터 값을 저장하는 Lambda 함수
Outbox 처리 큐에서 S3 key를 받아서 S3에서 임베딩 데이터를 읽고 Vector DB에 저장
"""
import json
import boto3
import os
import psycopg2
from datetime import datetime
import hashlib

# AWS 클라이언트 초기화
s3_client = boto3.client("s3", region_name='ap-northeast-2')

# 환경변수
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME")
EMBEDDING_BUCKET_DIRECTORY = os.environ.get("EMBEDDING_BUCKET_DIRECTORY")
RECOMMEND_DB_HOST = os.environ.get("RECOMMEND_DB_HOST")
RECOMMEND_DB_PORT = os.environ.get("RECOMMEND_DB_PORT", "3306")
RECOMMEND_DB_NAME = os.environ.get("RECOMMEND_DB_NAME")
RECOMMEND_DB_USER = os.environ.get("RECOMMEND_DB_USER")
RECOMMEND_DB_PASSWORD = os.environ.get("RECOMMEND_DB_PASSWORD")

def get_db_connection():
    """PostgreSQL 데이터베이스 연결을 생성합니다."""
    try:
        conn = psycopg2.connect(
            host=RECOMMEND_DB_HOST,
            port=int(RECOMMEND_DB_PORT),
            database=RECOMMEND_DB_NAME,
            user=RECOMMEND_DB_USER,
            password=RECOMMEND_DB_PASSWORD
        )
        return conn
    except Exception as e:
        print(f"Database connection error: {str(e)}")
        raise e

def get_embedding_data_from_s3(s3_key):
    """S3에서 임베딩 데이터를 읽어옵니다."""
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

def save_vector_and_reviews_to_db(embedding_data, restaurant_id):
    """Vector DB에 벡터 데이터와 리뷰를 하나의 트랜잭션으로 저장합니다."""
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        place_id = embedding_data.get('placeId')
        summary = embedding_data.get('summary', '')
        keywords = embedding_data.get('keywords', {})
        embeddings = embedding_data.get('embeddings', {})
        reviews = embedding_data.get('reviews', [])
        
        companion_vector = embeddings.get('companion', [])
        food_vector = embeddings.get('food', [])
        purpose_vector = embeddings.get('purpose', [])
        vibe_vector = embeddings.get('vibe', [])
        
        latitude = embedding_data.get('latitude', 0.0)
        longitude = embedding_data.get('longitude', 0.0)
        
        insert_vector_query = """
        INSERT INTO restaurant_vector 
        (id, place_id, companion_vector, food_vector, purpose_vector, vibe_vector, 
         latitude, longitude, created_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (place_id) DO NOTHING
        """
        
        cursor.execute(insert_vector_query, (
            restaurant_id,
            place_id,
            companion_vector,
            food_vector,
            purpose_vector,
            vibe_vector,
            latitude,
            longitude,
            datetime.now()
        ))
        
        if reviews:
            # 리뷰 데이터를 hash 기준으로 정렬하여 저장
            review_data = []
            for review in reviews:
                content = review.get('content', '')
                review_hash = hashlib.sha256(content.encode()).hexdigest()
                review_data.append((review_hash, content, place_id))
            
            insert_review_query = """
            INSERT INTO crawling_review 
            (hash, content, restaurant_id)
            VALUES (%s, %s, %s)
            ON CONFLICT (hash) DO NOTHING
            """
            cursor.executemany(insert_review_query, review_data)
        
        conn.commit()
        cursor.close()
        conn.close()
        
        return True
        
    except Exception as e:
        if conn:
            conn.rollback()
            conn.close()
        raise e

def handler(event, context):
    """
    Outbox 처리 큐에서 S3 key를 받아서 S3에서 임베딩 데이터를 조회한 후 Vector DB에 저장
    Input: SQS 메시지 {"s3Key": "xxx_embedding.json"}
    """
    print("Starting vector save process...")
    saved_count = 0
        
    # SQS 메시지 처리
    for record in event.get('Records', []):
        message_body = json.loads(record['body'])
        s3_key = message_body.get('s3Key')
        restaurant_id = message_body.get('restaurantId')
        print(f"Processing message for S3 key: {s3_key} restaurant_id: {restaurant_id}")
        
        if not s3_key:
            print("No S3 key found in message, skipping...")
            continue
        
        # S3에서 임베딩 데이터 읽기
        embedding_data = get_embedding_data_from_s3(s3_key)
        
        # 트랜잭션 진입 이전에 리뷰 데이터를 hash 기준으로 미리 정렬
        reviews = embedding_data.get('reviews', [])
        if reviews:
            review_data = []
            for review in reviews:
                content = review.get('content', '')
                review_hash = hashlib.sha256(content.encode()).hexdigest()
                review_data.append((review_hash, content, review))
            
            # hash 기준으로 정렬
            review_data.sort(key=lambda x: x[0])
            
            # 정렬된 순서로 원본 리뷰 배열 재구성
            sorted_reviews = [review for _, _, review in review_data]
            embedding_data['reviews'] = sorted_reviews
        
        # Vector DB와 리뷰를 하나의 트랜잭션으로 저장
        if save_vector_and_reviews_to_db(embedding_data, restaurant_id):
            saved_count += 1
            print(f"Successfully saved vector and reviews for placeId: {embedding_data.get('placeId', 'unknown')}")
        else:
            print(f"Failed to save vector and reviews for placeId: {embedding_data.get('placeId', 'unknown')}")
            
    
    print(f"Processing completed. Total saved: {saved_count}")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Vector save completed successfully",
            "savedCount": saved_count
        })
    }

if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {
        "Records": [
            {
                "body": json.dumps({
                    "s3Key": "test_embedding.json"
                })
            }
        ]
    }

    # 테스트를 위한 환경 변수 설정
    os.environ["S3_BUCKET_NAME"] = "test-bucket"
    os.environ["EMBEDDING_BUCKET_DIRECTORY"] = "embedding"
    
    handler(test_event, None)
