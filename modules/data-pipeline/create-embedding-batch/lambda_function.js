const AWS = require('aws-sdk');

// AWS SDK 초기화
const s3 = new AWS.S3();
const sqs = new AWS.SQS();

// 환경변수
const S3_BUCKET_NAME = process.env.S3_BUCKET_NAME;
const S3_REVIEW_BUCKET_DIRECTORY = process.env.S3_REVIEW_BUCKET_DIRECTORY;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const OPENAI_API_URL = 'https://api.openai.com/v1';

// 로깅 설정
const logger = {
    info: (message) => console.log(`[INFO] ${message}`),
    error: (message) => console.error(`[ERROR] ${message}`),
    warn: (message) => console.warn(`[WARN] ${message}`)
};

/**
 * 메인 핸들러 함수
 */
exports.handler = async (event, context) => {
    logger.info('Starting embedding processing...');

    // SQS 메시지 처리
    for (const record of event.Records) {
        const messageBody = JSON.parse(record.body);
        const s3Key = messageBody.s3Key || messageBody;

        logger.info(`Processing S3 key: ${s3Key}`);

        // S3에서 리뷰 데이터 읽기
        const reviews = await readReviewsFromS3(s3Key);
        logger.info(`Read ${reviews.length} reviews from S3`);

        // 리뷰를 20개씩 청크로 나누기
        const chunks = chunkReviews(reviews, 20);
        logger.info(`Created ${chunks.length} chunks`);

        // 각 청크별로 요약 생성
        const chunkSummaries = await processChunks(chunks);
        logger.info(`Generated ${chunkSummaries.length} chunk summaries`);

        // 최종 요약 생성
        const finalSummary = await createFinalSummary(chunkSummaries);
        logger.info('Generated final summary');

        // 키워드 추출
        const keywords = await extractKeywords(finalSummary);
        logger.info('Extracted keywords');

        // 임베딩 생성
        const embeddings = await generateEmbeddings(keywords);
        logger.info('Generated embeddings');

        // 결과를 S3에 업로드
        const result = {
            placeId: reviews[0]?.placeId,
            summary: finalSummary,
            keywords: keywords,
            embeddings: embeddings,
            processedAt: new Date().toISOString(),
            totalReviews: reviews.length
        };

        await uploadResultToS3(result, s3Key);
        logger.info('Uploaded results to S3');
    }

    return {
        statusCode: 200,
        body: JSON.stringify({ message: 'Processing completed successfully' })
    };
};

/**
 * S3에서 리뷰 데이터 읽기
 */
async function readReviewsFromS3(s3Key) {
    const fullKey = `${S3_REVIEW_BUCKET_DIRECTORY}/${s3Key}`;
    logger.info(`Reading from S3: ${S3_BUCKET_NAME}/${fullKey}`);

    const params = {
        Bucket: S3_BUCKET_NAME,
        Key: fullKey
    };

    const response = await s3.getObject(params).promise();
    const data = JSON.parse(response.Body.toString('utf-8'));

    return Array.isArray(data) ? data : [data];
}

/**
 * 리뷰를 청크로 나누기
 */
function chunkReviews(reviews, chunkSize) {
    const chunks = [];
    for (let i = 0; i < reviews.length; i += chunkSize) {
        chunks.push(reviews.slice(i, i + chunkSize));
    }
    return chunks;
}

/**
 * 각 청크별로 요약 생성
 */
async function processChunks(chunks) {
    const chunkPromises = chunks.map(async (chunk, index) => {
        logger.info(`Processing chunk ${index + 1}/${chunks.length}`);

        const reviewsText = chunk.map(review =>
            `리뷰 ${review.id}: ${review.content}`
        ).join('\n\n');

        const summary = await callOpenAI({
            model: 'gpt-4o-mini',
            messages: [
                {
                    role: 'system',
                    content: '당신은 한국어 리뷰를 요약하는 전문가입니다. 주어진 리뷰들을 간결하고 명확하게 요약해주세요.'
                },
                {
                    role: 'user',
                    content: `다음 리뷰들을 요약해주세요:\n\n${reviewsText}`
                }
            ],
            max_tokens: 500,
            temperature: 0.3
        });

        return summary;
    });

    return await Promise.all(chunkPromises);
}

/**
 * 최종 요약 생성
 */
async function createFinalSummary(chunkSummaries) {
    const combinedSummaries = chunkSummaries.join('\n\n');

    const finalSummary = await callOpenAI({
        model: 'gpt-4o-mini',
        messages: [
            {
                role: 'system',
                content: '당신은 여러 요약을 종합하여 하나의 완전한 요약을 만드는 전문가입니다.'
            },
            {
                role: 'user',
                content: `다음 요약들을 종합하여 하나의 완전한 요약을 만들어주세요:\n\n${combinedSummaries}`
            }
        ],
        max_tokens: 800,
        temperature: 0.3
    });

    return finalSummary;
}

/**
 * 키워드 추출
 */
async function extractKeywords(summary) {
    const response = await callOpenAI({
        model: 'gpt-4o-mini',
        messages: [
            {
                role: 'system',
                content: `당신은 한국어 리뷰를 분석하는 전문가입니다.
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
- JSON 형식으로만 응답`
            },
            {
                role: 'user',
                content: summary
            }
        ],
        response_format: { type: 'json_object' },
        max_tokens: 300,
        temperature: 0.1
    });

    return JSON.parse(response);
}

/**
 * 임베딩 생성
 */
async function generateEmbeddings(keywords) {
    const elements = [
        keywords.purpose,
        keywords.vibe,
        keywords.companion,
        keywords.food
    ].filter(element => element && element.trim() !== '');

    const embeddingPromises = elements.map(async (element) => {
        const embedding = await callOpenAIEmbedding(element);
        return {
            text: element,
            embedding: embedding
        };
    });

    const embeddings = await Promise.all(embeddingPromises);

    return {
        purpose: embeddings.find(e => e.text === keywords.purpose)?.embedding || [],
        vibe: embeddings.find(e => e.text === keywords.vibe)?.embedding || [],
        companion: embeddings.find(e => e.text === keywords.companion)?.embedding || [],
        food: embeddings.find(e => e.text === keywords.food)?.embedding || []
    };
}

/**
 * OpenAI API 호출 (Chat Completions)
 */
async function callOpenAI(params) {
    const response = await fetch(`${OPENAI_API_URL}/chat/completions`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${OPENAI_API_KEY}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(params)
    });

    if (!response.ok) {
        throw new Error(`OpenAI API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    return data.choices[0].message.content;
}

/**
 * OpenAI API 호출 (Embeddings)
 */
async function callOpenAIEmbedding(text) {
    const response = await fetch(`${OPENAI_API_URL}/embeddings`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${OPENAI_API_KEY}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            input: text,
            model: 'text-embedding-3-small'
        })
    });

    if (!response.ok) {
        throw new Error(`OpenAI API error: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    return data.data[0].embedding;
}

/**
 * 결과를 S3에 업로드
 */
async function uploadResultToS3(result, originalS3Key) {
    const fileName = originalS3Key.replace('.json', '_embedding.json');
    const key = `embedding/${fileName}`;

    logger.info(`Uploading result to S3: ${S3_BUCKET_NAME}/${key}`);

    const params = {
        Bucket: S3_BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(result, null, 2),
        ContentType: 'application/json'
    };

    await s3.putObject(params).promise();
    logger.info(`Successfully uploaded to S3: ${key}`);
} 