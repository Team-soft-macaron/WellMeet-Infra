#!/bin/bash

# Lambda Layer 빌드 스크립트
# 이 스크립트는 pymysql과 의존성을 포함한 Lambda Layer를 생성합니다.

set -e

# 디렉토리 생성
mkdir -p python/lib/python3.9/site-packages

# pip으로 의존성 설치
pip install -r requirements.txt -t python/lib/python3.9/site-packages/

# 불필요한 파일들 제거 (용량 최적화)
find python/lib/python3.9/site-packages/ -name "*.pyc" -delete
find python/lib/python3.9/site-packages/ -name "__pycache__" -type d -exec rm -rf {} +
find python/lib/python3.9/site-packages/ -name "*.dist-info" -type d -exec rm -rf {} +
find python/lib/python3.9/site-packages/ -name "tests" -type d -exec rm -rf {} +

echo "Lambda Layer 빌드 완료!"
echo "python/ 디렉토리를 압축하여 AWS Lambda Layer로 업로드하세요."
