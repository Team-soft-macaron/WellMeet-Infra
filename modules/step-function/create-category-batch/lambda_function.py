import json
import os
import boto3
from typing import List, Dict, Any
from openai import OpenAI
import logging
import sys

# 환경 변수
BUCKET_DIRECTORY = os.getenv("BUCKET_DIRECTORY")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME")

# OpenAI 클라이언트 초기화
client = OpenAI()

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


def lambda_handler(event, context):
    S3_KEY = event["S3_KEY"]
    print(S3_KEY)
    """Lambda 1: 카테고리 추출 배치 생성만 수행"""
    try:
        logger.info("=== 카테고리 추출 배치 생성 시작 ===")

        # 1. S3에서 리뷰 데이터 가져오기
        logger.info("S3에서 리뷰 데이터 로딩 중...")
        reviews = get_reviews_from_s3()
        logger.info(f"S3에서 {len(reviews)}개의 리뷰를 성공적으로 로드했습니다")

        # 2. 카테고리 추출을 위한 배치 작업 생성
        logger.info("카테고리 추출 배치 작업 생성 중...")
        extraction_batch_id = create_extraction_batch(reviews)
        logger.info(f"추출 배치 작업이 생성되었습니다. 배치 ID: {extraction_batch_id}")

        # Step Function으로 전달할 데이터
        return {
            "statusCode": 200,
            "body": {
                "extraction_batch_id": extraction_batch_id,
                "reviews": reviews,  # 리뷰 리스트도 함께 반환
                "review_count": len(reviews),
            },
        }

    except Exception as e:
        logger.error("배치 생성 중 오류가 발생했습니다")
        logger.error(f"오류 내용: {str(e)}")
        return {"statusCode": 500, "body": {"error": str(e)}}


def get_reviews_from_s3() -> List[Dict[str, Any]]:
    """S3에서 리뷰 데이터를 가져오는 함수"""
    try:
        response = s3_client.get_object(
            Bucket=S3_BUCKET_NAME, Key=BUCKET_DIRECTORY + S3_KEY
        )
        content = response["Body"].read().decode("utf-8")
        reviews = json.loads(content)
        return reviews
    except Exception as e:
        raise Exception(f"Failed to get reviews from S3: {str(e)}")


def create_extraction_batch(reviews: List[Dict[str, Any]]) -> str:
    """카테고리 추출을 위한 배치 작업 생성"""
    batch_input_file_path = "/tmp/extraction_batch_input.jsonl"

    # JSONL 파일 생성
    with open(batch_input_file_path, "w", encoding="utf-8") as f:
        for review in reviews:
            request = {
                "custom_id": review["id"],
                "method": "POST",
                "url": "/v1/chat/completions",
                "body": {
                    "model": "gpt-4o-mini",
                    "messages": [
                        {
                            "role": "system",
                            "content": """당신은 한국어 리뷰를 분석하는 전문가입니다.
사용자의 리뷰를 분석하여 정확히 4가지 정보만 추출해주세요.
추출할 정보:
1. purpose (목적): 모임의 목적 - 생일, 기념일, 회식, 데이트, 가족모임 등
2. vibe (분위기): 원하는 분위기 - 조용한, 활기찬, 로맨틱한, 편안한, 고급스러운 등
3. companion (동행자): 함께 가는 사람 - 가족, 친구, 연인, 동료, 부모님 등
4. food (음식): 선호하는 음식 종류 - 한식, 일식, 양식, 중식, 이탈리안 등
응답 규칙:
- 모든 값은 반드시 한글 String으로 작성
- 여러 특성이 있으면 "~고"로 연결 (예: "조용하고 편안한")
- 언급되지 않은 정보는 ""으로 표시
- JSON 형식으로만 응답""",
                        },
                        {"role": "user", "content": review["content"]},
                    ],
                    "response_format": {"type": "json_object"},
                },
            }
            f.write(json.dumps(request, ensure_ascii=False) + "\n")

    # 파일 업로드 및 배치 작업 생성
    with open(batch_input_file_path, "rb") as f:
        batch_input_file = client.files.create(file=f, purpose="batch")

    batch = client.batches.create(
        input_file_id=batch_input_file.id,
        endpoint="/v1/chat/completions",
        completion_window="24h",
    )

    return batch.id


if __name__ == "__main__":
    lambda_handler(None, None)
