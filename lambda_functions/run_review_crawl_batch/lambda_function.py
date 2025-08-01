import json
import boto3
import os
from typing import List, Dict, Any
import logging
import time
from urllib.parse import unquote_plus

# 로깅 설정
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS 클라이언트 초기화
s3_client = boto3.client("s3")
batch_client = boto3.client("batch")

# 환경변수
JOB_QUEUE = os.environ.get("BATCH_JOB_QUEUE", "fargate-spot-review-crawler-job-queue")
JOB_DEFINITION = os.environ.get("BATCH_JOB_DEFINITION", "batch-review-job-definition")
RESTAURANT_BUCKET_DIRECTORY = os.environ.get("RESTAURANT_BUCKET_DIRECTORY", "restaurant")
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "wellmeet-data-pipeline")


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    S3 이벤트를 처리하고 JSON 파일에서 place_id를 추출하여 Batch 작업을 실행

    Args:
        event: S3 이벤트 정보
        context: Lambda 실행 컨텍스트

    Returns:
        처리 결과
    """
    try:
        total_submitted_jobs = 0
        # S3 이벤트에서 버킷과 키 정보 추출
        for record in event["Records"]:
            # S3 이벤트 정보 파싱
            s3_event = record["s3"]
            bucket_name = s3_event["bucket"]["name"]
            object_key = s3_event["object"]["key"]
            object_key = unquote_plus(object_key)
            print(f"Processing file: s3://{bucket_name}/{object_key}")

            logger.info(f"Processing file: s3://{bucket_name}/{object_key}")

            # S3에서 파일 읽기
            response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
            file_content = response["Body"].read().decode("utf-8")
            data = json.loads(file_content)

            logger.info(f"Successfully loaded JSON from {object_key}")

            # place_id 추출 및 처리
            place_ids = extract_place_ids(data)
            logger.info(f"Found {len(place_ids)} place_ids in {object_key}")
            total_submitted_jobs += len(place_ids)

            # 각 place_id에 대해 작업 실행
            job_responses = []
            for place_id in place_ids[:3]:
                job_response = submit_batch_job(
                    place_id=place_id, source_bucket=bucket_name, source_key=object_key
                )
                if job_response:
                    job_responses.append(job_response)

            logger.info(f"Submitted {len(job_responses)} batch jobs for {object_key}")

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "Successfully processed S3 event",
                    "jobs_submitted": total_submitted_jobs,
                }
            ),
        }
    except s3_client.exceptions.NoSuchKey as e:
        logger.error(f"No such key: {object_key}")
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def extract_place_ids(data: Any) -> List[str]:
    """
    JSON 데이터에서 place_id 값들을 추출

    Args:
        data: JSON 데이터 (리스트 또는 딕셔너리)

    Returns:
        place_id 리스트
    """
    place_ids = []

    # 데이터가 리스트인 경우
    if isinstance(data, list):
        for item in data:
            if isinstance(item, dict) and "placeId" in item:
                place_id = item.get("placeId")
                if place_id:
                    place_ids.append(str(place_id))

    return list(set(place_ids))


def submit_batch_job(
    place_id: str, source_bucket: str, source_key: str
) -> Dict[str, Any]:
    """
    AWS Batch 작업 제출

    Args:
        place_id: 처리할 place_id
        source_bucket: 소스 S3 버킷
        source_key: 소스 S3 키

    Returns:
        Batch 작업 응답
    """
    job_name = f"process-place-{place_id}-{int(time.time())}"

    response = batch_client.submit_job(
        jobName=job_name,
        jobQueue=JOB_QUEUE,
        jobDefinition=JOB_DEFINITION,
        parameters={},
        containerOverrides={
            "environment": [
                {"name": "PLACE_ID", "value": place_id},
                {"name": "SOURCE_BUCKET", "value": source_bucket},
                {"name": "SOURCE_KEY", "value": source_key},
            ]
        },
    )

    logger.info(f"Submitted batch job {job_name} for place_id: {place_id}")
    return response



def process_large_file(
    bucket: str, key: str, chunk_size: int = 1024 * 1024
) -> List[str]:
    """
    대용량 JSON 파일을 스트리밍으로 처리
    """
    place_ids = []

    response = s3_client.get_object(Bucket=bucket, Key=key)

    # 스트리밍 파싱 대신 일반 파싱 사용 (ijson 없이)
    file_content = response["Body"].read().decode("utf-8")
    data = json.loads(file_content)

    # 데이터가 리스트인 경우
    if isinstance(data, list):
        for obj in data:
            if isinstance(obj, dict) and "placeId" in obj:
                place_ids.append(str(obj["placeId"]))

    return place_ids


if __name__ == "__main__":
    # S3 이벤트 형식으로 테스트 이벤트 생성
    test_event = {
        "Records": [
            {
                "s3": {
                    "bucket": {
                        "name": "wellmeet-data-pipeline"
                    },
                    "object": {
                        "key": "restaurant/강남역 식당.json"
                    }
                }
            }
        ]
    }
    
    # 핸들러 실행
    result = handler(test_event, None)
    print(f"Result: {result}")
