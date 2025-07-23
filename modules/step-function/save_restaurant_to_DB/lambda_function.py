import json
import boto3
import os
import pymysql
import pg8000
from urllib.parse import unquote_plus
import uuid

s3_client = boto3.client("s3")


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


def get_recommend_db_connection():
    """recommend 데이터베이스 연결을 생성합니다. (PostgreSQL with pg8000)"""
    return pg8000.connect(
        host=os.environ.get("RECOMMEND_DB_HOST"),
        user=os.environ.get("RECOMMEND_DB_USER"),
        password=os.environ.get("RECOMMEND_DB_PASSWORD"),
        database=os.environ.get("RECOMMEND_DB_NAME"),
        port=int(os.environ.get("RECOMMEND_DB_PORT")),
    )


def save_restaurants_to_db(restaurants_data):
    """식당 데이터를 두 개의 DB에 저장합니다."""
    restaurant_connection = None
    recommend_connection = None
    restaurant_cursor = None
    recommend_cursor = None
    saved_count = 0

    try:
        restaurant_connection = get_restaurant_db_connection()
        recommend_connection = get_recommend_db_connection()
        restaurant_cursor = restaurant_connection.cursor()
        recommend_cursor = recommend_connection.cursor()

        # 각 식당 데이터를 DB에 저장
        for restaurant in restaurants_data:
            # 각 restaurant마다 새로운 UUID 생성
            restaurant_id = str(uuid.uuid4())

            place_id = restaurant.get("placeId")
            name = restaurant.get("name")
            address = restaurant.get("address")
            latitude = restaurant.get("latitude") or 0.0
            longitude = restaurant.get("longitude") or 0.0
            thumbnail = restaurant.get("thumbnail") or ""

            try:
                # Restaurant DB에 저장 (MySQL)
                restaurant_insert_query = """
                    INSERT IGNORE INTO restaurant (
                        id, name, address, latitude, longitude, thumbnail
                    ) VALUES (%s, %s, %s, %s, %s, %s)
                """

                restaurant_cursor.execute(
                    restaurant_insert_query,
                    (
                        restaurant_id,
                        name,
                        address,
                        latitude,
                        longitude,
                        thumbnail,
                    ),
                )

                # Recommend DB에 저장 (PostgreSQL with pg8000)
                # pg8000은 %s 대신 숫자 플레이스홀더 사용
                recommend_insert_query = """
                    INSERT INTO restaurant_vector (
                        restaurant_id, place_id, latitude, longitude
                    ) VALUES (%s, %s, %s, %s)
                    ON CONFLICT (place_id) DO NOTHING
                """

                recommend_cursor.execute(
                    recommend_insert_query,
                    (
                        restaurant_id,
                        place_id,
                        latitude,
                        longitude,
                    ),
                )

                saved_count += 1

            except Exception as e:
                print(f"Error saving restaurant {place_id}: {str(e)}")
                continue

        # 변경사항 커밋
        restaurant_connection.commit()
        recommend_connection.commit()
        print(f"Successfully saved {saved_count} restaurants to both databases")

    except Exception as e:
        print(f"Database error: {str(e)}")
        if restaurant_connection:
            restaurant_connection.rollback()
        if recommend_connection:
            recommend_connection.rollback()
        raise e

    finally:
        if restaurant_cursor:
            restaurant_cursor.close()
        if recommend_cursor:
            recommend_cursor.close()
        if restaurant_connection:
            restaurant_connection.close()
        if recommend_connection:
            recommend_connection.close()

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

    # 테스트를 위한 환경 변수 설정
    os.environ["RESTAURANT_DB_HOST"] = "localhost"
    os.environ["RESTAURANT_DB_USER"] = "root"
    os.environ["RESTAURANT_DB_PASSWORD"] = "password"
    os.environ["RESTAURANT_DB_NAME"] = "wellmeet"
    os.environ["RECOMMEND_DB_HOST"] = "localhost"
    os.environ["RECOMMEND_DB_USER"] = "postgres"
    os.environ["RECOMMEND_DB_PASSWORD"] = "password"
    os.environ["RECOMMEND_DB_NAME"] = "wellmeet_recommendation"
    os.environ["RECOMMEND_DB_PORT"] = "5432"

    handler(test_event, None)
