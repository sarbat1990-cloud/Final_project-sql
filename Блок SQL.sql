USE customer_final;

# ==========================================
# ПУНКТ 1: Клиенты с непрерывной историей за год (12 месяцев)
# ==========================================
SELECT  
    t.ID_client,
    -- 1. Средний чек за весь период 
    SUM(t.Sum_payment) / COUNT(t.Id_check) AS avg_check_global,
    -- 2. Средняя сумма покупок за месяц (строго делим на 12 месяцев года)
    SUM(t.Sum_payment) / 12.0 AS avg_amount_per_month,
    -- 3. Количество всех операций за период
    COUNT(t.Id_check) AS total_operations
FROM transactions t
WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01' -- Исключаем 1 июня 2016, чтобы получить ровно год
GROUP BY t.ID_client
-- Условие непрерывности: покупки в каждом из 12 месяцев периода
HAVING COUNT(DISTINCT DATE_FORMAT(t.date_new, '%Y-%m')) = 12;


# ==========================================
# ПУНКТ 2: Аналитика в разрезе месяцев
# ==========================================
WITH global_totals AS (
    SELECT 
        COUNT(Id_check) AS total_ops_year,
        SUM(Sum_payment) AS total_sum_year
    FROM transactions
    WHERE date_new >= '2015-06-01' AND date_new < '2016-06-01'
),
monthly_metrics AS (
    SELECT 
        DATE_FORMAT(t.date_new, '%Y-%m') AS month_id,
        COUNT(DISTINCT t.Id_check) AS monthly_checks,       
        SUM(t.Sum_payment) AS monthly_sum,                   
        COUNT(DISTINCT t.ID_client) AS monthly_active_users,
        -- Общее количество операций в конкретном месяце
        COUNT(t.Id_check) AS monthly_total_ops 
    FROM transactions t
    WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01'
    GROUP BY DATE_FORMAT(t.date_new, '%Y-%m')
),
gender_metrics AS (
    SELECT 
        DATE_FORMAT(t.date_new, '%Y-%m') AS month_id,
        
        -- % соотношение операций по полу внутри месяца (обрабатываем и NULL, и пустые значения)
        ROUND(COUNT(CASE WHEN c.Gender = 'M' THEN t.Id_check END) * 100.0 / COUNT(t.Id_check), 2) AS pct_ops_M,
        ROUND(COUNT(CASE WHEN c.Gender = 'F' THEN t.Id_check END) * 100.0 / COUNT(t.Id_check), 2) AS pct_ops_F,
        ROUND(COUNT(CASE WHEN c.Gender IS NULL OR c.Gender NOT IN ('M', 'F') THEN t.Id_check END) * 100.0 / COUNT(t.Id_check), 2) AS pct_ops_NA,
        
        -- Доля затрат по полу внутри месяца от общей суммы месяца
        ROUND(SUM(CASE WHEN c.Gender = 'M' THEN t.Sum_payment ELSE 0 END) * 100.0 / SUM(t.Sum_payment), 2) AS pct_sum_M,
        ROUND(SUM(CASE WHEN c.Gender = 'F' THEN t.Sum_payment ELSE 0 END) * 100.0 / SUM(t.Sum_payment), 2) AS pct_sum_F,
        ROUND(SUM(CASE WHEN c.Gender IS NULL OR c.Gender NOT IN ('M', 'F') THEN t.Sum_payment ELSE 0 END) * 100.0 / SUM(t.Sum_payment), 2) AS pct_sum_NA
    FROM transactions t
    LEFT JOIN customer_final c ON t.ID_client = c.Id_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01'
    GROUP BY DATE_FORMAT(t.date_new, '%Y-%m')
)
SELECT 
    mm.month_id AS `Месяц`,
    mm.monthly_sum / mm.monthly_checks AS `Средний чек в месяц`,
    mm.monthly_total_ops AS `Количество операций в месяц`, 
    mm.monthly_active_users AS `Количество клиентов в месяц`, 
    ROUND(mm.monthly_total_ops * 100.0 / gt.total_ops_year, 2) AS `Доля от общего кол-ва операций за год, %`,
    ROUND(mm.monthly_sum * 100.0 / gt.total_sum_year, 2) AS `Доля от общей суммы операций за год, %`,
    
    gm.pct_ops_M AS `Операции M, %`, gm.pct_ops_F AS `Операции F, %`, gm.pct_ops_NA AS `Операции NA, %`,
    gm.pct_sum_M AS `Затраты M, %`, gm.pct_sum_F AS `Затраты F, %`, gm.pct_sum_NA AS `Затраты NA, %`
FROM monthly_metrics mm
CROSS JOIN global_totals gt
JOIN gender_metrics gm ON mm.month_id = gm.month_id
ORDER BY mm.month_id;


# ==========================================
# ПУНКТ 3: Возрастные группы (Всего за период + Поквартально)
# ==========================================
WITH client_age_groups AS (
    SELECT 
        Id_client,
        CASE 
            WHEN Age IS NULL THEN 'No Data'
            WHEN Age BETWEEN 0 AND 9 THEN '0-9'
            WHEN Age BETWEEN 10 AND 19 THEN '10-19'
            WHEN Age BETWEEN 20 AND 29 THEN '20-29'
            WHEN Age BETWEEN 30 AND 39 THEN '30-39'
            WHEN Age BETWEEN 40 AND 49 THEN '40-49'
            WHEN Age BETWEEN 50 AND 59 THEN '50-59'
            WHEN Age BETWEEN 60 AND 69 THEN '60-69'
            ELSE '70+' 
        END AS age_group
    FROM customer_final
),
quarterly_aggregates AS (
    SELECT 
        cg.age_group,
        CONCAT(YEAR(t.date_new), ' - Q', QUARTER(t.date_new)) AS quarter_id,
        SUM(t.Sum_payment) AS q_sum,
        COUNT(t.Id_check) AS q_ops,
        AVG(t.Sum_payment) AS q_avg_check
    FROM transactions t
    JOIN client_age_groups cg ON t.ID_client = cg.Id_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01'
    GROUP BY cg.age_group, YEAR(t.date_new), QUARTER(t.date_new)
),
total_per_age_group AS (
    SELECT 
        cg.age_group,
        SUM(t.Sum_payment) AS total_sum_group,
        COUNT(t.Id_check) AS total_ops_group
    FROM transactions t
    JOIN client_age_groups cg ON t.ID_client = cg.Id_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01'
    GROUP BY cg.age_group
)
SELECT 
    qa.age_group AS `Возрастная группа`,
    tpag.total_sum_group AS `Сумма группы за ВЕСЬ период`,
    tpag.total_ops_group AS `Кол-во операций группы за ВЕСЬ период`,
    qa.quarter_id AS `Квартал`,
    qa.q_sum AS `Сумма затрат в квартал`,
    qa.q_ops AS `Количество операций в квартал`,
    qa.q_avg_check AS `Средний чек в квартале`,
    -- Считаем внутреннюю структуру: какой процент от годового итога группы пришелся на конкретный квартал
    ROUND(qa.q_ops * 100.0 / tpag.total_ops_group, 2) AS `Доля операций от итога группы, %`,
    ROUND(qa.q_sum * 100.0 / tpag.total_sum_group, 2) AS `Доля затрат от итога группы, %`
FROM quarterly_aggregates qa
JOIN total_per_age_group tpag ON qa.age_group = tpag.age_group
ORDER BY qa.age_group, qa.quarter_id;