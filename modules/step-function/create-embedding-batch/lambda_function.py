import json
import os
import uuid
import boto3
from typing import List, Dict, Any
from datetime import datetime
import logging
import sys
import urllib.request
import urllib.error

# 환경 변수
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME")
REVIEW_BUCKET_DIRECTORY = os.getenv("REVIEW_BUCKET_DIRECTORY")
CATEGORY_BUCKET_DIRECTORY = os.getenv("CATEGORY_BUCKET_DIRECTORY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

# S3 클라이언트 초기화
s3_client = boto3.client("s3")

# 로거 설정
logger = logging.getLogger()
logger.setLevel(logging.INFO)
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(logging.INFO)
formatter = logging.Formatter("%(asctime)s - %(levelname)s - %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)


def handler(event, context):
    logger.info(event)
    print(event["body"])
    S3_KEY = event["S3_KEY"]
    print(S3_KEY)
    """Lambda 2: 카테고리 배치 확인, 저장 및 임베딩 배치 생성"""
    try:
        logger.info("=== 카테고리 배치 확인 및 처리 시작 ===")

        # Step Function에서 전달받은 데이터
        extraction_batch_id = event["body"]["extraction_batch_id"]
        reviews = get_reviews_from_s3(REVIEW_BUCKET_DIRECTORY, S3_KEY)

        logger.info(f"배치 ID: {extraction_batch_id}")
        logger.info(f"리뷰 개수: {len(reviews)}")

        # 1. 배치 상태 확인
        logger.info("배치 상태 확인 중...")

        # urllib로 배치 상태 확인
        req = urllib.request.Request(
            f"https://api.openai.com/v1/batches/{extraction_batch_id}",
            headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
        )

        try:
            with urllib.request.urlopen(req) as response:
                batch = json.loads(response.read().decode())
        except urllib.error.HTTPError as e:
            raise Exception(f"Batch retrieve failed: {e.read().decode()}")

        if batch["status"] == "in_progress" or batch["status"] == "validating":
            # 완료되지 않았으면 즉시 에러 반환
            logger.info(
                f"배치가 아직 완료되지 않았습니다. 현재 상태: {batch['status']}"
            )
            return {
                "statusCode": 202,
                "body": {
                    "error": "Batch not completed",
                    "batch_id": extraction_batch_id,
                    "status": batch["status"],
                },
            }
        elif batch["status"] != "completed":
            raise Exception(f"Batch failed: {batch}")
        logger.info("카테고리 추출 배치가 완료되었습니다!")

        # 2. 배치 결과 가져오기
        logger.info("배치 결과 가져오기...")
        extraction_results = get_batch_results(batch["output_file_id"])
        logger.info(f"추출 결과 {len(extraction_results)}개를 받았습니다")

        # 3. 추출된 카테고리를 리뷰에 매핑
        logger.info("카테고리를 리뷰에 매핑 중...")
        reviews_with_categories = map_categories_to_reviews(reviews, extraction_results)
        logger.info("카테고리 매핑이 완료되었습니다")

        # 4. 카테고리가 추가된 리뷰를 S3에 저장
        logger.info("카테고리 데이터를 S3에 저장 중...")
        category_s3_key = save_categories_to_s3(
            CATEGORY_BUCKET_DIRECTORY, reviews_with_categories, S3_KEY
        )
        logger.info(f"카테고리 데이터가 S3에 저장되었습니다: {category_s3_key}")

        # 5. 임베딩 배치 생성
        logger.info("임베딩 배치 작업 생성 중...")
        embedding_batch_id = create_embedding_batch(reviews_with_categories)
        logger.info(f"임베딩 배치 작업이 생성되었습니다. 배치 ID: {embedding_batch_id}")

        # Step Function으로 전달할 데이터
        return {
            "statusCode": 200,
            "body": {
                "s3_key": S3_KEY,
                "embedding_batch_id": embedding_batch_id,
                "processed_count": len(reviews_with_categories),
            },
        }

    except Exception as e:
        logger.error("처리 중 오류가 발생했습니다")
        logger.error(f"오류 내용: {str(e)}")
        raise Exception(f"Failed to create embedding batch: {str(e)}")


def get_batch_results(output_file_id: str) -> List[Dict[str, Any]]:
    """배치 결과 파일 가져오기"""
    try:
        # urllib로 파일 내용 가져오기
        req = urllib.request.Request(
            f"https://api.openai.com/v1/files/{output_file_id}/content",
            headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
        )

        with urllib.request.urlopen(req) as response:
            file_content = response.read().decode()

        # JSONL 파싱
        results = []
        for line in file_content.split("\n"):
            if line.strip():
                results.append(json.loads(line))

        return results
    except Exception as e:
        raise Exception(f"Failed to get batch results: {str(e)}")


def map_categories_to_reviews(
    reviews: List[Dict[str, Any]], extraction_results: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """추출된 카테고리를 리뷰에 매핑"""
    # 결과를 ID로 인덱싱
    results_by_id = {}
    for result in extraction_results:
        review_id = result["custom_id"].split("_")[0]
        if result["response"]["status_code"] == 200:
            content = json.loads(
                result["response"]["body"]["choices"][0]["message"]["content"]
            )
            results_by_id[review_id] = content

    # 리뷰에 카테고리 추가
    for review in reviews:
        review_id = review["id"]
        if review_id in results_by_id:
            review["categories"] = results_by_id[review_id]
        else:
            review["categories"] = {
                "purpose": "",
                "vibe": "",
                "companion": "",
                "food": "",
            }

    return reviews


def get_reviews_from_s3(BUCKET_DIRECTORY: str, S3_KEY: str) -> List[Dict[str, Any]]:
    """S3에서 리뷰 데이터를 가져오는 함수"""
    try:
        key = f"{BUCKET_DIRECTORY}/{S3_KEY}.json"
        logger.info(f"key: {key}")
        response = s3_client.get_object(Bucket=S3_BUCKET_NAME, Key=key)
        content = response["Body"].read().decode("utf-8")
        reviews = json.loads(content)
        return reviews
    except Exception as e:
        raise Exception(f"Failed to get reviews from S3: {str(e)}")


def save_categories_to_s3(
    BUCKET_DIRECTORY: str, reviews: List[Dict[str, Any]], S3_KEY: str
) -> str:
    """카테고리가 추가된 리뷰 데이터를 S3에 저장"""
    try:
        # 타임스탬프 생성
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        # S3 키 생성
        category_key = f"{BUCKET_DIRECTORY}/{S3_KEY}.json"

        # JSON으로 변환
        content = json.dumps(reviews, ensure_ascii=False, indent=2)

        # S3에 업로드
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=category_key,
            Body=content.encode("utf-8"),
            ContentType="application/json",
        )

        logger.info(f"카테고리 데이터 저장 완료: s3://{S3_BUCKET_NAME}/{category_key}")

        return category_key

    except Exception as e:
        raise Exception(f"Failed to save categories to S3: {str(e)}")


def create_embedding_batch(reviews: List[Dict[str, Any]]) -> str:
    """임베딩을 위한 배치 작업 생성"""
    batch_input_file_path = "/tmp/embedding_batch_input.jsonl"

    # JSONL 파일 생성
    with open(batch_input_file_path, "w", encoding="utf-8") as f:
        for review in reviews:
            categories = review.get("categories", {})
            # 각 카테고리별로 임베딩 요청 생성
            for category, keyword in categories.items():
                if keyword:  # 빈 문자열이 아닌 경우만
                    request = {
                        "custom_id": f"{review['id']}_{category}_{uuid.uuid4()}",
                        "method": "POST",
                        "url": "/v1/embeddings",
                        "body": {
                            "model": "text-embedding-3-small",
                            "input": keyword,
                            "dimensions": 768,
                        },
                    }
                    f.write(json.dumps(request, ensure_ascii=False) + "\n")

    # 파일 업로드 - urllib 사용
    with open(batch_input_file_path, "rb") as f:
        file_content = f.read()

    # multipart/form-data 경계 문자열
    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"

    # multipart 본문 생성
    body = []
    body.append(f"------{boundary}".encode())
    body.append(b'Content-Disposition: form-data; name="purpose"')
    body.append(b"")
    body.append(b"batch")
    body.append(f"------{boundary}".encode())
    body.append(
        b'Content-Disposition: form-data; name="file"; filename="embedding_batch_input.jsonl"'
    )
    body.append(b"Content-Type: application/jsonl")
    body.append(b"")
    body.append(file_content)
    body.append(f"------{boundary}--".encode())

    body_data = b"\r\n".join(body)

    # 파일 업로드 요청
    req = urllib.request.Request(
        "https://api.openai.com/v1/files",
        data=body_data,
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": f"multipart/form-data; boundary=----{boundary}",
        },
    )

    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode())
            file_id = result["id"]
    except urllib.error.HTTPError as e:
        raise Exception(f"File upload failed: {e.read().decode()}")

    # 배치 작업 생성 - urllib 사용
    batch_data = json.dumps(
        {
            "input_file_id": file_id,
            "endpoint": "/v1/embeddings",
            "completion_window": "24h",
        }
    ).encode("utf-8")

    batch_req = urllib.request.Request(
        "https://api.openai.com/v1/batches",
        data=batch_data,
        headers={
            "Authorization": f"Bearer {OPENAI_API_KEY}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(batch_req) as response:
            result = json.loads(response.read().decode())
            return result["id"]
    except urllib.error.HTTPError as e:
        raise Exception(f"Batch creation failed: {e.read().decode()}")


if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {"body": {"extraction_batch_id": "batch_xxx", "reviews": []}}
    handler(test_event, None)
