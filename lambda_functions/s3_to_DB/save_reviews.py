import json
import boto3
from sqlalchemy import create_engine, Column, Integer, String, Float, DateTime
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from datetime import datetime
import os
from typing import List, Dict
from urllib.parse import unquote_plus

# SQLAlchemy Base
Base = declarative_base()

# CrawlingReview Entity (Python version matching Java entity)
class CrawlingReview(Base):
    __tablename__ = 'crawling_review'

    id = Column(Integer, primary_key=True, autoincrement=True)
    content = Column(String(1000), nullable=False)
    created_at = Column(DateTime, nullable=True)
    restaurant_id = Column(Integer, nullable=False)

class S3ToRDSLoader:
    def __init__(self, 
                 aws_region: str,
                 s3_bucket: str,
                 s3_key: str,
                 db_host: str = None,
                 db_port: int = None,
                 db_name: str = None,
                 db_user: str = None,
                 db_password: str = None):
        # S3 client setup
        self.s3_client = boto3.client(
            's3',
            region_name=aws_region
        )
        self.s3_bucket = s3_bucket
        self.s3_key = s3_key

    def read_from_s3(self) -> list:
        """Read JSON data from S3 and print it"""
        try:
            response = self.s3_client.get_object(Bucket=self.s3_bucket, Key=self.s3_key)
            content = response['Body'].read().decode('utf-8')
            data = json.loads(content)
            print(f"Successfully read {len(data)} records from S3")
            print(json.dumps(data, ensure_ascii=False, indent=2))
            return data
        except Exception as e:
            print(f"Error reading from S3: {e}")
            raise

    def load_data(self):
        """Main method to load data from S3 and print it"""
        print("Starting data load from S3...")
        self.read_from_s3()
        print("Data load complete.")

# Usage example
if __name__ == "__main__":
    config = {
        # AWS Configuration
        'aws_region': os.getenv('AWS_REGION'),
        # 's3_bucket': os.getenv('S3_BUCKET_NAME'),
        's3_bucket': "naver-map-review",
        's3_key': os.getenv('S3_KEY_NAME'),
    }
    loader = S3ToRDSLoader(**config)
    loader.load_data()

# Lambda handler for S3 upload trigger
def handler(event, context):
    """
    AWS Lambda handler to process S3 upload events and print data from S3.
    """
    try:
        s3_record = event['Records'][0]['s3']
        s3_bucket = s3_record['bucket']['name']
        s3_key = unquote_plus(s3_record['object']['key'])
    except (KeyError, IndexError) as e:
        print(f"Malformed S3 event: {e}")
        raise
    config = {
        'aws_region': os.getenv('AWS_REGION'),
        's3_bucket': s3_bucket,
        's3_key': s3_key,
    }
    loader = S3ToRDSLoader(**config)
    loader.load_data()
    return {
        'statusCode': 200,
        'body': f"Loaded and printed data from {s3_bucket}/{s3_key}."
    }
