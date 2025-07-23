import json
import gzip
import boto3
import os
import pg8000
from urllib.parse import unquote_plus

s3_client = boto3.client("s3")


def get_recommend_db_connection():
    """recommend 데이터베이스 연결을 생성합니다. (PostgreSQL with pg8000)"""
    return pg8000.connect(
        host=os.environ.get("RECOMMEND_DB_HOST"),
        user=os.environ.get("RECOMMEND_DB_USER"),
        password=os.environ.get("RECOMMEND_DB_PASSWORD"),
        database=os.environ.get("RECOMMEND_DB_NAME"),
        port=int(os.environ.get("RECOMMEND_DB_PORT")),
    )


def save_reviews_to_db(reviews_data):
    """크롤링 리뷰 데이터를 DB에 저장합니다."""
    connection = None
    cursor = None
    saved_count = 0
    skipped_count = 0

    try:
        connection = get_recommend_db_connection()
        cursor = connection.cursor()

        # placeId별로 리뷰 그룹화
        reviews_by_place = {}
        for review in reviews_data:
            place_id = review.get("placeId")
            if place_id:
                if place_id not in reviews_by_place:
                    reviews_by_place[place_id] = []
                reviews_by_place[place_id].append(review)

        # 각 placeId별로 restaurant_id 조회 후 리뷰 저장
        for place_id, place_reviews in reviews_by_place.items():
            try:
                # restaurant_vector에서 해당 place_id의 id 조회
                cursor.execute(
                    "SELECT id FROM restaurant_vector WHERE place_id = %s", (place_id,)
                )
                result = cursor.fetchone()

                if not result:
                    print(
                        f"Restaurant not found for place_id: {place_id}, skipping {len(place_reviews)} reviews"
                    )
                    skipped_count += len(place_reviews)
                    continue

                restaurant_vector_id = result[0]

                # 해당 restaurant의 모든 리뷰 저장
                for review in place_reviews:
                    try:
                        review_id = review.get("id")  # hash 값
                        content = review.get("content", "")
                        embeddings = review.get("embeddings", {})

                        # 벡터 데이터 추출 (없으면 768차원 0 벡터)
                        vibe_vector = embeddings.get("vibe", [0.0] * 768)
                        food_vector = embeddings.get("food", [0.0] * 768)
                        companion_vector = embeddings.get("companion", [0.0] * 768)
                        purpose_vector = embeddings.get("purpose", [0.0] * 768)

                        # 벡터를 PostgreSQL 형식 문자열로 변환
                        vibe_vector_str = "[" + ",".join(map(str, vibe_vector)) + "]"
                        food_vector_str = "[" + ",".join(map(str, food_vector)) + "]"
                        companion_vector_str = (
                            "[" + ",".join(map(str, companion_vector)) + "]"
                        )
                        purpose_vector_str = (
                            "[" + ",".join(map(str, purpose_vector)) + "]"
                        )

                        # CrawlingReview 테이블에 저장
                        insert_query = """
                            INSERT INTO crawling_review (
                                content, hash, restaurant_id,
                                vibe_vector, food_vector, companion_vector, purpose_vector
                            ) VALUES (
                                %s, %s, %s,
                                %s::vector, %s::vector, %s::vector, %s::vector
                            )
                            ON CONFLICT (hash) DO NOTHING
                        """

                        cursor.execute(
                            insert_query,
                            (
                                content,
                                review_id,
                                restaurant_vector_id,
                                vibe_vector_str,
                                food_vector_str,
                                companion_vector_str,
                                purpose_vector_str,
                            ),
                        )

                        saved_count += 1

                    except Exception as e:
                        print(f"Error saving review {review.get('id')}: {str(e)}")
                        continue

            except Exception as e:
                print(f"Error processing place_id {place_id}: {str(e)}")
                continue

        # 변경사항 커밋
        connection.commit()
        print(
            f"Successfully saved {saved_count} reviews, skipped {skipped_count} reviews"
        )

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
    S3에서 압축된 리뷰 데이터를 읽어와서 DB에 저장
    Input: {"SEARCH_QUERY": "강남역-reviews", "S3_DIRECTORY": "reviews", "S3_BUCKET_NAME": "my-bucket"}
    Output: {"reviewCount": 123, "query": "강남역-reviews"}
    """
    query = event.get("SEARCH_QUERY", "공덕역-reviews")
    review_bucket_directory = event.get("S3_DIRECTORY")
    s3_bucket_name = event.get("S3_BUCKET_NAME")

    # 파일 키 생성 (.json.gz 확장자)
    file_key = f"{review_bucket_directory}/{unquote_plus(query)}.json.gz"
    print(f"file_key: {file_key}")

    try:
        # S3에서 압축 파일 읽기
        print(f"Reading file from S3: {file_key}")
        response = s3_client.get_object(Bucket=s3_bucket_name, Key=file_key)

        # gzip 압축 해제
        compressed_content = response["Body"].read()
        decompressed_content = gzip.decompress(compressed_content)
        reviews_data = json.loads(decompressed_content.decode("utf-8"))

        # 데이터가 리스트인지 확인
        if not isinstance(reviews_data, list):
            raise ValueError("Expected list of reviews but got different data type")

        print(f"Found {len(reviews_data)} reviews in S3")

        # DB에 리뷰 데이터 저장
        saved_count = save_reviews_to_db(reviews_data)
        print(f"Saved {saved_count} reviews to database")

        return {
            "reviewCount": saved_count,
            "totalReviews": len(reviews_data),
            "query": query,
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        raise e


if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {
        "SEARCH_QUERY": "gongdeok-reviews",
        "S3_DIRECTORY": "reviews",
        "S3_BUCKET_NAME": "my-review-bucket",
    }

    # 테스트를 위한 환경 변수 설정
    os.environ["RECOMMEND_DB_HOST"] = "localhost"
    os.environ["RECOMMEND_DB_USER"] = "postgres"
    os.environ["RECOMMEND_DB_PASSWORD"] = "password"
    os.environ["RECOMMEND_DB_NAME"] = "wellmeet_recommendation"
    os.environ["RECOMMEND_DB_PORT"] = "3306"

    handler(test_event, None)
