import json
import boto3
import os
import pymysql
from urllib.parse import unquote_plus
import uuid

s3_client = boto3.client("s3")


def get_db_connection():
    """데이터베이스 연결을 생성합니다."""
    return pymysql.connect(
        host=os.environ.get("DB_HOST"),
        user=os.environ.get("DB_USER"),
        password=os.environ.get("DB_PASSWORD"),
        database=os.environ.get("DB_NAME"),
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
    )


def save_restaurants_to_db(restaurants_data):
    """식당 데이터를 DB에 저장합니다."""
    connection = None
    cursor = None
    saved_count = 0
    restaurant_id = uuid.uuid4()

    try:
        connection = get_db_connection()
        cursor = connection.cursor()

        # 각 식당 데이터를 DB에 저장
        for restaurant in restaurants_data:
            id = restaurant_id
            place_id = restaurant.get("placeId")
            name = restaurant.get("name")
            address = restaurant.get("address")
            latitude = restaurant.get("latitude", 0.0)
            longitude = restaurant.get("longitude", 0.0)
            thumbnail = restaurant.get("thumbnail", "")

            # placeId가 없거나 필수 필드가 없으면 건너뛰기
            if not place_id or not name or not address:
                print(
                    f"Skipping restaurant due to missing required fields: {restaurant}"
                )
                continue

            try:
                # INSERT ... ON DUPLICATE KEY UPDATE 사용 (placeId가 unique key이므로)
                insert_query = """
                    INSERT IGNORE INTO restaurant (
                        id, place_id, name, address, latitude, longitude, thumbnail
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                """

                cursor.execute(
                    insert_query,
                    (
                        id,
                        place_id,
                        name,
                        address,
                        latitude,
                        longitude,
                        thumbnail,
                    ),
                )
                saved_count += 1

            except Exception as e:
                print(f"Error saving restaurant {place_id}: {str(e)}")
                continue

        # 변경사항 커밋
        connection.commit()
        print(f"Successfully saved {saved_count} restaurants to database")

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


def handler(event, context):
    """
    S3에서 식당 데이터를 읽어와서 DB에 저장하고 place_id 리스트를 추출
    Input: {"SEARCH_QUERY": "강남역 맛집", "S3_DIRECTORY": "restaurants", "S3_BUCKET_NAME": "my-bucket"}
    Output: {"placeIds": [{"placeId": "123"}, {"placeId": "124"}, ...]}
    """
    query = event.get("SEARCH_QUERY", "공덕역 식당")
    restaurant_bucket_directory = event.get("S3_DIRECTORY")
    s3_bucket_name = event.get("S3_BUCKET_NAME")

    # 파일 키 생성 (query 기반) - URL encoding 적용
    file_key = f"{restaurant_bucket_directory}/{unquote_plus(query)}.json"

    try:
        # S3에서 파일 읽기
        response = s3_client.get_object(Bucket=s3_bucket_name, Key=file_key)
        restaurants_data = json.loads(response["Body"].read().decode("utf-8"))

        # 데이터가 리스트인지 확인
        if not isinstance(restaurants_data, list):
            raise ValueError("Expected list of restaurants but got different data type")

        print(f"Found {len(restaurants_data)} restaurants in S3")

        # DB에 식당 데이터 저장
        saved_count = save_restaurants_to_db(restaurants_data)
        print(f"Saved {saved_count} restaurants to database")

        # place_id를 객체로 추출
        place_ids = []
        for restaurant in restaurants_data:
            place_id = restaurant.get("placeId")
            if place_id:
                place_ids.append({"placeId": place_id})  # 객체로 변경

        print(f"Extracted {len(place_ids)} place IDs")
        print(place_ids)

        return {"placeIds": place_ids, "query": query}

    except Exception as e:
        print(f"Error: {str(e)}")
        raise e


if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {
        "SEARCH_QUERY": "gongdeok-restaurants-placeid",
        "S3_DIRECTORY": "restaurants",
        "S3_BUCKET_NAME": "my-restaurant-bucket",
    }

    # 테스트를 위한 환경 변수 설정 (실제 Lambda에서는 환경 변수로 설정)
    os.environ["DB_HOST"] = "localhost"
    os.environ["DB_USER"] = "root"
    os.environ["DB_PASSWORD"] = "password"
    os.environ["DB_NAME"] = "wellmeet"

    handler(test_event, None)
