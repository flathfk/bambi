-- 부하 테스트용 시드 데이터.
--
-- 빈 DB 에 부하를 걸면 `/api/feed/public` 이 빈 배열을 반환해 **아무것도 측정되지 않는다**.
-- 실제 화면과 같은 일을 하게 하려면 카드·작성자·좋아요·관심사가 모두 있어야 한다.
--
-- 규모 근거: 운영은 사용자 27명·공개 카드 20건 수준이다. 그 규모에서는 병목이 안 보이므로
-- **작성자 200명 · 카드 2,000건 · 좋아요 20,000건**으로 늘려 잡는다. 카드 수가 늘면
-- FeedService 가 후보를 넓게 읽는 구간(RANKING_POOL_SIZE)과 IN 쿼리들이 실제로 일한다.
--
-- ⚠️ 로컬 전용. 운영 DB 에 절대 실행하지 않는다.
--
-- 실행:
--   docker compose exec -T postgres psql -U bambi -d bambi -f - < ../loadtest/seed.sql

BEGIN;

-- 1) 작성자 200명. 비밀번호 해시는 로그인 측정용 계정에만 진짜 값을 넣는다(아래 3번).
INSERT INTO service.users (email, password_hash, display_name, username, public_id)
SELECT
    'load' || i || '@bambi.test',
    '$2a$10$notarealhashnotarealhashnotarealhashnotarealhashno',
    '부하테스트' || i,
    'load' || i,
    gen_random_uuid()
FROM generate_series(1, 200) AS i
ON CONFLICT (email) DO NOTHING;

-- 2) 공개 카드 2,000건. created_at 을 최근 30일에 흩어 랭킹의 신선도 점수가 갈리게 한다.
INSERT INTO service.cards (user_id, title, summary, why_for_you, visibility, created_at)
SELECT
    u.id,
    '부하 테스트 리포트 ' || g,
    '요약 본문입니다. 피드 카드가 실제로 렌더할 만한 길이를 흉내내기 위해 두 문장 정도로 채웁니다. '
        || '검색·랭킹 로직은 본문 길이에 영향받지 않지만 응답 크기는 영향받습니다.',
    '이 주제를 저장하신 적이 있어 추천합니다.',
    'PUBLIC',
    now() - (random() * interval '30 days')
FROM generate_series(1, 2000) AS g
JOIN LATERAL (
    SELECT id FROM service.users
    WHERE email LIKE 'load%@bambi.test'
    ORDER BY (g * 7919 + id) % 200
    LIMIT 1
) AS u ON TRUE;

-- 3) 좋아요 20,000건. 카드마다 편차를 둬야 랭킹의 인기 점수가 실제로 정렬을 바꾼다.
INSERT INTO service.likes (card_id, user_id)
SELECT c.id, u.id
FROM service.cards c
JOIN LATERAL (
    SELECT id FROM service.users
    WHERE email LIKE 'load%@bambi.test'
    ORDER BY random()
    LIMIT (random() * 20)::int
) AS u ON TRUE
WHERE c.title LIKE '부하 테스트 리포트 %'
ON CONFLICT DO NOTHING;

COMMIT;

-- 확인
SELECT
    (SELECT count(*) FROM service.users WHERE email LIKE 'load%@bambi.test') AS users,
    (SELECT count(*) FROM service.cards WHERE visibility = 'PUBLIC')          AS public_cards,
    (SELECT count(*) FROM service.likes)                                      AS likes;
