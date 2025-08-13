/*
    1. 리뷰 데이터를 읽어온다.
    2. 리뷰 데이터를 20개씩 청크로 나눈다.
    3. 각 청크별로 요약을 생성한다.
    4. 최종 요약을 생성한다.
    5. 키워드를 추출한다.
    6. 임베딩을 생성한다.
    7. 결과를 S3에 업로드한다.
    8. SQS에 메시지를 전송하여 식당 메타데이터 저장을 트리거한다.
*/
import { S3Client, GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { SQSClient, SendMessageCommand } from '@aws-sdk/client-sqs';

// AWS SDK 초기화
const s3Client = new S3Client({ region: 'ap-northeast-2' }); // 원하는 리전으로 변경
const sqsClient = new SQSClient({ region: 'ap-northeast-2' });

// 환경변수
const S3_BUCKET_NAME = process.env.S3_BUCKET_NAME;
const S3_REVIEW_BUCKET_DIRECTORY = process.env.S3_REVIEW_BUCKET_DIRECTORY;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const SAVE_RESTAURANT_QUEUE_URL = process.env.SAVE_RESTAURANT_QUEUE_URL;
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
export const handler = async (event, context) => {
    logger.info('Starting embedding processing...');

    // SQS 메시지 처리
    for (const record of event.Records) {
        const messageBody = JSON.parse(record.body);
        const reviewS3Key = messageBody.reviewS3Key;

        logger.info(`Processing S3 key: ${reviewS3Key}`);

        // S3에서 리뷰 데이터 읽기
        const data = await readDataFromS3(reviewS3Key);
        const reviews = data.reviews;
        logger.info(`Read ${reviews.length} reviews from S3`);

        // 리뷰를 20개씩 청크로 나누기
        const chunks = chunkReviews(reviews, 20);
        logger.info(`Created ${chunks.length} chunks`);

        // 각 청크별로 요약 생성
        const chunkSummaries = await processChunks(chunks);
        logger.info(`Generated ${chunks.length} chunk summaries`);

        // 최종 요약 생성
        const finalSummary = await createFinalSummary(chunkSummaries);
        logger.info('Generated final summary');

        // 키워드 추출
        const keywords = await extractKeywords(finalSummary);
        logger.info('Extracted keywords');

        // 임베딩 생성
        const embeddings = await generateEmbeddings(keywords);
        logger.info('Generated embeddings');

        // 결과를 S3에 업로드 (restaurant_info와 reviews 포함)
        const result = {
            ...data, // 식당 메타데이터 전체 포함
            summary: finalSummary,
            keywords: keywords,
            embeddings: embeddings,
            processedAt: new Date().toISOString(),
            totalReviews: reviews.length
        };

        await uploadResultToS3(result, reviewS3Key);
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
async function readDataFromS3(reviewS3Key) {
    const fullKey = `${S3_REVIEW_BUCKET_DIRECTORY}/${reviewS3Key}`;
    logger.info(`Reading from S3: ${S3_BUCKET_NAME}/${fullKey}`);

    const params = {
        Bucket: S3_BUCKET_NAME,
        Key: fullKey
    };

    try {
        const response = await s3Client.send(new GetObjectCommand(params));
        // 응답 본문 처리를 위한 스트림에서 데이터 읽기
        const bodyContents = await streamToString(response.Body);
        const data = JSON.parse(bodyContents);

        // reviews 키 안에 있는 객체를 반환
        if (data) {
            return data;
        } else {
            logger.warn('No reviews found in data, returning empty array');
            return [];
        }
    } catch (error) {
        logger.error(`Error reading from S3: ${error.message}`);
        throw error;
    }
}

/**
 * 스트림을 문자열로 변환
 */
async function streamToString(stream) {
    const chunks = [];
    for await (const chunk of stream) {
        chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf-8');
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
                    content: '당신은 한국어 리뷰를 요약하는 전문가입니다. 주어진 리뷰들을 간결하고 명확하게 요약해주세요. 단, 모임의 목적, 식당의 분위기 및 서비스, 동행한 사람, 식당의 음식 정보를 포함해야 합니다.'
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
                content: '당신은 여러 요약을 종합하여 하나의 완전한 요약을 만드는 전문가입니다. 단, 모임의 목적, 식당의 분위기 및 서비스, 동행한 사람, 식당의 음식 정보를 포함해야 합니다.'
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
1. purpose (목적) : 모임의 목적
2. vibe (분위기 및 서비스) : 식당의 분위기
3. companion (동행자) : 함께 간 사람
4. food (음식) : 식당의 음식
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
 * 결과를 S3에 업로드하고 SQS에 메시지 전송
 */
async function uploadResultToS3(result, reviewS3Key) {
    const fileName = reviewS3Key.replace('.json', '_embedding.json');
    const key = `embedding/${fileName}`;

    logger.info(`Uploading result to S3: ${S3_BUCKET_NAME}/${key}`);

    const params = {
        Bucket: S3_BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(result, null, 2),
        ContentType: 'application/json'
    };

    try {
        // S3에 업로드
        await s3Client.send(new PutObjectCommand(params));
        logger.info(`Successfully uploaded to S3: ${key}`);

        // SQS에 메시지 전송
        await sendMessageToSQS({
            s3Key: key
        });
        logger.info(`Successfully sent message to SQS for key: ${key}`);

    } catch (error) {
        logger.error(`Error in uploadResultToS3: ${error.message}`);
        throw error;
    }
}

/**
 * SQS에 메시지 전송
 */
async function sendMessageToSQS(data) {
    const params = {
        QueueUrl: SAVE_RESTAURANT_QUEUE_URL,
        MessageBody: JSON.stringify(data),
        MessageAttributes: {
            'MessageType': {
                DataType: 'String',
                StringValue: 'restaurant_save_request'
            }
        }
    };

    try {
        await sqsClient.send(new SendMessageCommand(params));
        logger.info('Message sent to SQS successfully');
    } catch (error) {
        logger.error(`Error sending message to SQS: ${error.message}`);
        throw error;
    }
}

// 환경변수 설정 (테스트용)
if (!process.env.S3_BUCKET_NAME) {
    process.env.S3_BUCKET_NAME = 'test-bucket';
}
if (!process.env.S3_REVIEW_BUCKET_DIRECTORY) {
    process.env.S3_REVIEW_BUCKET_DIRECTORY = 'review';
}
if (!process.env.OPENAI_API_KEY) {
    process.env.OPENAI_API_KEY = 'test-api-key';
}
if (!process.env.SAVE_RESTAURANT_QUEUE_URL) {
    process.env.SAVE_RESTAURANT_QUEUE_URL = 'https://sqs.ap-northeast-2.amazonaws.com/123456789012/SaveRestaurantQueue'; // 실제 SQS URL로 변경
}

// 테스트 이벤트 (Lambda 환경에서는 주석 처리 필요)
if (process.env.NODE_ENV === 'development') {
    const testEvent = {
        Records: [
            {
                body: JSON.stringify({ reviewS3Key: '21053857.json' })
            }
        ]
    };

    // handler 실행
    handler(testEvent, {}).then(result => {
        console.log('Test result:', result);
    }).catch(error => {
        console.error('Test error:', error);
    });
}