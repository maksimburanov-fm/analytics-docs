with users_base as 
(
select user_id, max(phone) as phone
FROM spark_bsns_vlt.msp_ref_users
where phone is not null
group by user_id
)
, fill_phones as 
(
select 
	regexp_replace(coalesce(p.user_phone,u.phone),'[^0-9]','','g') as phone
	, p.order_id 
	, p.status 
	, p.merchant_id 
	, p.pan_mask 
	, p.bill_amount
	, p.created_at::date as cr_date
	, p.param1 
	, p.bank_alias 
FROM spark_bsns_vlt.msp_ref_pay_transactions p
	left join users_base u
		on p.param1 = u.user_id::varchar
where p.status in ('success')
) 
, pan_phones as
(
select 
	distinct
		first_value(phone) over (partition by pan_mask order by nullif(btrim(phone), ''), cr_date desc) as phone 
		, pan_mask 
from fill_phones
where pan_mask is not null
	and pan_mask != ''
)
, tr_w_phones as
(
select 
	regexp_replace(coalesce(f.phone , p.phone),'^8','7') as phone
	, f.order_id 
	, f.merchant_id 
	, sum(f.bill_amount) as price
	, min(f.cr_date) as cr_date
	, max(f.bank_alias) as bank_alias
from fill_phones f
	left join  pan_phones p 
		on f.pan_mask = p.pan_mask
where coalesce(f.phone , p.phone) is not null
group by coalesce(f.phone , p.phone), f.order_id, f.merchant_id
)
select tp.*, up.user_id
from tr_w_phones tp
	left join spark_bsns_vlt.msp_ref_users up
		on tp.phone = up.phone