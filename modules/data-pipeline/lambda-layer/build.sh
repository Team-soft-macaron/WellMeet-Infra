#!/bin/bash

# AWS Lambda Layer Docker 빌드 스크립트
set -e

echo "AWS Lambda Layer 빌드를 시작합니다..."

# requirements.txt 파일 존재 확인
if [ ! -f "requirements.txt" ]; then
   echo "ERROR: requirements.txt 파일이 없습니다!"
   echo "현재 디렉토리에 requirements.txt 파일을 생성해주세요."
   exit 1
fi

echo "requirements.txt 내용:"
cat requirements.txt
echo

# 기존 빌드 결과물 정리
echo "기존 빌드 결과물 정리 중..."
rm -rf lambda-layer.zip

# Docker 이미지 빌드
echo "Docker 이미지 빌드 중..."
docker build -t lambda-layer-builder .

# 컨테이너 실행하여 Layer 파일 추출
echo "Layer 파일 추출 중..."
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint cp -v "$(pwd)":/output lambda-layer-builder lambda-layer.zip /output/

# 결과 확인
if [ -f "lambda-layer.zip" ]; then
   echo "Lambda Layer 빌드 완료!"
   echo "생성된 파일 정보:"
   ls -lh lambda-layer.zip
   echo
   echo "다음 단계:"
   echo "1. AWS CLI를 사용하여 Layer 업로드:"
   echo "   aws lambda publish-layer-version \\"
   echo "     --layer-name pymysql-layer \\"
   echo "     --zip-file fileb://lambda-layer.zip \\"
   echo "     --compatible-runtimes python3.9"
   echo
   echo "2. 또는 AWS 콘솔에서 lambda-layer.zip 파일을 직접 업로드하세요."
else
   echo "ERROR: Layer 빌드에 실패했습니다!"
   exit 1
fi

docker rmi lambda-layer-builder

echo "빌드 프로세스가 완료되었습니다."
