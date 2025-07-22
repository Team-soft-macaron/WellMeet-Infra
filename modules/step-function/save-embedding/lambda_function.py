import json
import os
import boto3
import gzip
from typing import List, Dict, Any
from datetime import datetime
import logging
import sys
import urllib.request
import urllib.error

# 환경 변수
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME")
CATEGORY_BUCKET_DIRECTORY = os.getenv("CATEGORY_BUCKET_DIRECTORY")
EMBEDDING_BUCKET_DIRECTORY = os.getenv("EMBEDDING_BUCKET_DIRECTORY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
# S3_KEY = os.getenv("S3_KEY")

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
    """Lambda 3: 임베딩 배치 완료 확인 및 최종 처리"""
    try:
        logger.info("=== 임베딩 배치 완료 확인 시작 ===")
        print(event["body"])

        # Step Function에서 전달받은 데이터
        embedding_batch_id = event["body"]["embedding_batch_id"]
        s3_key = event["body"]["s3_key"]

        logger.info(f"임베딩 배치 ID: {embedding_batch_id}")
        logger.info(f"S3 키: {s3_key}")

        # 1. 배치 상태 확인
        logger.info("[단계 1/5] 배치 상태 확인 중...")

        # urllib로 배치 상태 확인
        req = urllib.request.Request(
            f"https://api.openai.com/v1/batches/{embedding_batch_id}",
            headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
        )

        try:
            with urllib.request.urlopen(req) as response:
                batch = json.loads(response.read().decode())
        except urllib.error.HTTPError as e:
            raise Exception(f"Batch retrieve failed: {e.read().decode()}")

        if batch["status"] == "in_progress" or batch["status"] == "validating":
            logger.info(
                f"배치가 아직 완료되지 않았습니다. 현재 상태: {batch['status']}"
            )
            return {
                "statusCode": 202,
                "body": {
                    "error": "Batch not completed",
                    "batch_id": embedding_batch_id,
                    "status": batch["status"],
                },
            }
        elif batch["status"] != "completed":
            raise Exception(f"Batch failed: {batch}")
        logger.info("배치가 성공적으로 완료되었습니다!")

        # 2. 임베딩 결과 가져오기
        logger.info("[단계 2/5] 임베딩 결과 가져오기...")
        embedding_results = get_batch_results(batch["output_file_id"])
        logger.info(f"임베딩 결과 {len(embedding_results)}개를 받았습니다")

        # 3. 카테고리 데이터 가져오기
        logger.info("[단계 3/5] S3에서 카테고리 데이터 로딩 중...")
        reviews_with_categories = get_categories_from_s3(s3_key)
        logger.info(f"{len(reviews_with_categories)}개의 리뷰를 로드했습니다")

        # 4. 임베딩 결과를 리뷰에 매핑
        logger.info("[단계 4/5] 임베딩을 리뷰에 매핑 중...")
        final_reviews = map_embeddings_to_reviews(
            reviews_with_categories, embedding_results
        )
        logger.info("임베딩 매핑이 성공적으로 완료되었습니다")

        # 5. 최종 결과를 S3에 저장
        logger.info("[단계 5/5] 최종 결과를 S3에 저장 중...")
        final_s3_key = save_final_results_to_s3(final_reviews, s3_key)
        logger.info(f"최종 결과가 S3에 저장되었습니다: {final_s3_key}")

        logger.info("=== 모든 처리가 완료되었습니다 ===")
        logger.info(f"총 처리된 리뷰 수: {len(final_reviews)}개")

        return {
            "statusCode": 200,
            "body": {
                "message": "All processing completed successfully",
                "processed_count": len(final_reviews),
                "final_s3_key": final_s3_key,
            },
        }

    except Exception as e:
        logger.error("처리 중 오류가 발생했습니다")
        logger.error(f"오류 내용: {str(e)}")
        raise Exception(f"Failed to save embedding: {str(e)}")


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


def get_categories_from_s3(category_s3_key: str) -> List[Dict[str, Any]]:
    s3_key = f"{CATEGORY_BUCKET_DIRECTORY}/{category_s3_key}.json"
    """S3에서 카테고리 데이터를 가져오는 함수"""
    try:
        response = s3_client.get_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
        )
        content = response["Body"].read().decode("utf-8")
        reviews = json.loads(content)
        return reviews
    except Exception as e:
        raise Exception(f"Failed to get categories from S3: {str(e)}")


def map_embeddings_to_reviews(
    reviews: List[Dict[str, Any]], embedding_results: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """임베딩 결과를 리뷰에 매핑"""
    # 결과를 ID와 카테고리로 인덱싱
    embeddings_by_id = {}
    for result in embedding_results:
        if result["response"]["status_code"] == 200:
            custom_id = result["custom_id"]
            review_id, category, _ = custom_id.rsplit("_", 2)

            if review_id not in embeddings_by_id:
                embeddings_by_id[review_id] = {}

            embedding_data = result["response"]["body"]["data"][0]["embedding"]
            embeddings_by_id[review_id][category] = embedding_data

    # 리뷰에 임베딩 추가
    for review in reviews:
        review_id = review["id"]
        if review_id in embeddings_by_id:
            review["embeddings"] = embeddings_by_id[review_id]
        else:
            review["embeddings"] = {}

    return reviews


def save_final_results_to_s3(reviews: List[Dict[str, Any]], s3_key: str) -> str:
    """처리된 최종 결과를 S3에 저장"""
    try:
        result_key = f"{EMBEDDING_BUCKET_DIRECTORY}/{s3_key}.json.gz"

        logger.info("=== 파일 저장 프로세스 시작 ===")

        # 1. JSON 콘텐츠 생성 (포매팅 없이)
        logger.info("JSON 콘텐츠 생성 중...")
        json_content = json.dumps(reviews, ensure_ascii=False, separators=(",", ":"))
        logger.info(f"JSON 크기: {len(json_content):,} bytes")

        # 2. gzip으로 압축
        logger.info("압축 중...")
        compressed_content = gzip.compress(json_content.encode("utf-8"))
        logger.info(f"압축된 크기: {len(compressed_content):,} bytes")
        logger.info(f"압축률: {len(compressed_content)/len(json_content)*100:.1f}%")

        # 3. S3에 업로드
        logger.info("S3에 업로드 중...")
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=result_key,
            Body=compressed_content,
            ContentType="application/json",
            ContentEncoding="gzip",
        )

        logger.info(f"✓ 최종 파일 업로드 완료: s3://{S3_BUCKET_NAME}/{result_key}")
        logger.info("=== 파일 저장 프로세스 완료 ===")

        return result_key

    except Exception as e:
        raise Exception(f"Failed to save final results to S3: {str(e)}")


if __name__ == "__main__":
    # 테스트용 이벤트
    test_event = {
        "body": {
            "embedding_batch_id": "batch_xxx",
            "s3_key": "categories/reviews_with_categories_20241120_123456.json",
        }
    }
    handler(test_event, None)
