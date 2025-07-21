import json
import boto3
import os
from urllib.parse import unquote_plus

s3_client = boto3.client("s3")


def handler(event, context):
    """
    S3에서 식당 데이터를 읽어와서 place_id 리스트를 추출

    Input: {"query": "강남역 맛집"}
    Output: [123, 124, 125 ...]
    """

    query = event.get("SEARCH_QUERY", "공덕역 식당")
    restaurant_bucket_directory = event.get("RESTAURANT_BUCKET_DIRECTORY")
    s3_bucket_name = event.get("S3_BUCKET_NAME")

    # 파일 키 생성 (query 기반) - URL encoding 적용
    file_key = f"{restaurant_bucket_directory}/{unquote_plus(query)}.json"

    try:
        # S3에서 파일 읽기
        response = s3_client.get_object(Bucket=s3_bucket_name, Key=file_key)
        restaurants_data = json.loads(response["Body"].read().decode("utf-8"))

        # place_id 추출
        place_ids = []

        if isinstance(restaurants_data, list):
            for restaurant in restaurants_data:
                place_id = restaurant.get("placeId")

                if place_id:
                    place_ids.append(place_id)
        print(place_ids)
        return {"placeIds": place_ids, "query": query}

    except Exception as e:
        print(f"Error: {str(e)}")
        raise e


if __name__ == "__main__":
    test_event = {"query": "gongdeok-restaurants-placeid"}
    handler(test_event, None)
