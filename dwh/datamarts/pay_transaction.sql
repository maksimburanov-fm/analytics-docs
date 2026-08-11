CREATE OR REPLACE VIEW VW_PAY_TRANSACTIONS AS
WITH users_base AS (
    SELECT
        user_id,
        NULLIF(
            MAX(regexp_replace(phone, '[^0-9]', '', 'g')),
            ''
        ) AS phone
    FROM spark_bsns_vlt.msp_ref_users
    WHERE phone IS NOT NULL
      AND btrim(phone) <> ''
    GROUP BY user_id
)
SELECT
    regexp_replace(
        COALESCE(
            NULLIF(
                regexp_replace(btrim(p.user_phone), '[^0-9]', '', 'g'),
                ''
            ),
            u.phone
        ),
        '^8',
        '7'
    ) AS phone,
    p.order_id,
    p.merchant_id,
    SUM(p.bill_amount) AS price,
    p.created_at::date AS cr_date,
    MAX(
        CASE
            WHEN p.merchant_id = 563748 THEN 'superapp'
            ELSE p.bank_alias
        END
    ) AS bank_alias
FROM spark_bsns_vlt.msp_ref_pay_transactions p
LEFT JOIN users_base u
    ON NULLIF(btrim(p.param1), '') = u.user_id::varchar
WHERE p.status = 'success'
  AND COALESCE(
        NULLIF(
            regexp_replace(btrim(p.user_phone), '[^0-9]', '', 'g'),
            ''
        ),
        u.phone
      ) IS NOT NULL
GROUP BY
    regexp_replace(
        COALESCE(
            NULLIF(
                regexp_replace(btrim(p.user_phone), '[^0-9]', '', 'g'),
                ''
            ),
            u.phone
        ),
        '^8',
        '7'
    ),
    p.order_id,
    p.merchant_id,
    p.created_at::date;
