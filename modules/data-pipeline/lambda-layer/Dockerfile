# AWS Lambda Python 3.9 런타임과 동일한 환경 사용
FROM public.ecr.aws/lambda/python:3.9

# 작업 디렉토리 설정
WORKDIR /opt

# 빌드에 필요한 도구 설치
RUN yum update -y && \
    yum install -y zip && \
    yum clean all

# requirements.txt 복사
COPY requirements.txt .

# Lambda Layer 구조로 패키지 설치
RUN mkdir -p python/lib/python3.9/site-packages && \
    pip install -r requirements.txt -t python/lib/python3.9/site-packages/ --no-cache-dir

# 불필요한 파일들 제거 (용량 최적화)
RUN find python/lib/python3.9/site-packages/ -name "*.pyc" -delete && \
    find python/lib/python3.9/site-packages/ -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find python/lib/python3.9/site-packages/ -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find python/lib/python3.9/site-packages/ -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true && \
    find python/lib/python3.9/site-packages/ -name "*.egg-info" -type d -exec rm -rf {} + 2>/dev/null || true

# Layer zip 파일 생성 - 수정된 부분
RUN zip -r9 lambda-layer.zip python/

# 빌드 결과 확인
RUN echo "Lambda Layer 빌드 완료!" && \
    echo "생성된 파일 크기:" && \
    ls -lh lambda-layer.zip && \
    echo "파일 구조 확인:" && \
    unzip -l lambda-layer.zip | head -10
    