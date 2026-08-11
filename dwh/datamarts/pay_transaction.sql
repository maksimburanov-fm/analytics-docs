CREATE OR REPLACE VIEW VW_PAY_TRANSACTIONS AS
WITH users_base AS (
    SELECT
        user_id,
        MAX(regexp_replace(phone, '[^0-9]', '', 'g')) AS phone
    FROM spark_bsns_vlt.msp_ref_users
    WHERE phone IS NOT NULL
      AND btrim(phone) <> ''
    GROUP BY user_id
),
users_by_phone AS (
    SELECT
        phone,
        user_id
    FROM (
        SELECT
            regexp_replace(phone, '[^0-9]', '', 'g') AS phone,
            user_id,
            ROW_NUMBER() OVER (
                PARTITION BY regexp_replace(phone, '[^0-9]', '', 'g')
                ORDER BY user_id DESC
            ) AS rn
        FROM spark_bsns_vlt.msp_ref_users
        WHERE phone IS NOT NULL
          AND btrim(phone) <> ''
    ) src
    WHERE rn = 1
),
fill_phones AS (
    SELECT
        regexp_replace(
            COALESCE(NULLIF(btrim(p.user_phone), ''), u.phone),
            '[^0-9]',
            '',
            'g'
        ) AS phone,
        p.order_id,
        p.status,
        p.merchant_id,
        p.pan_mask,
        p.bill_amount,
        p.created_at::date AS cr_date,
        p.param1,
        p.bank_alias
    FROM spark_bsns_vlt.msp_ref_pay_transactions p
    LEFT JOIN users_base u
        ON p.param1 = u.user_id::varchar
    WHERE p.status = 'success'
),
pan_phones AS (
    SELECT
        pan_mask,
        phone
    FROM (
        SELECT
            pan_mask,
            phone,
            ROW_NUMBER() OVER (
                PARTITION BY pan_mask
                ORDER BY
                    CASE
                        WHEN phone IS NOT NULL AND btrim(phone) <> '' THEN 0
                        ELSE 1
                    END,
                    cr_date DESC
            ) AS rn
        FROM fill_phones
        WHERE pan_mask IS NOT NULL
          AND btrim(pan_mask) <> ''
    ) src
    WHERE rn = 1
),
tr_w_phones AS (
    SELECT
        regexp_replace(
            COALESCE(NULLIF(btrim(f.phone), ''), p.phone),
            '^8',
            '7'
        ) AS phone,
        f.order_id,
        f.merchant_id,
        SUM(f.bill_amount) AS price,
        MIN(f.cr_date) AS cr_date,
        MAX(
            CASE
                WHEN f.merchant_id = 563748 THEN 'superapp'
                ELSE f.bank_alias
            END
        ) AS bank_alias
    FROM fill_phones f
    LEFT JOIN pan_phones p
        ON f.pan_mask = p.pan_mask
    WHERE COALESCE(NULLIF(btrim(f.phone), ''), p.phone) IS NOT NULL
    GROUP BY
        regexp_replace(
            COALESCE(NULLIF(btrim(f.phone), ''), p.phone),
            '^8',
            '7'
        ),
        f.order_id,
        f.merchant_id
)
SELECT
    tp.phone,
    tp.order_id,
    tp.merchant_id,
    tp.price,
    tp.cr_date,
    tp.bank_alias,
    up.user_id
FROM tr_w_phones tp
LEFT JOIN users_by_phone up
    ON tp.phone = up.phone;
