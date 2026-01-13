CREATE OR REPLACE TABLE `automacoes-481202.case_telecom.tbdc_faturamento_mes_a_mes` as(
WITH vendas_base AS (
  SELECT
    SAFE_CAST(valor AS NUMERIC) AS valor,
    SAFE_CAST(data_venda AS DATE) AS data_venda
  FROM `automacoes-481202.case_telecom.base_vendas`
  WHERE SAFE_CAST(data_venda AS DATE) IS NOT NULL
    AND SAFE_CAST(valor AS NUMERIC) IS NOT NULL
),

faturamento_mensal AS (
  SELECT
    FORMAT_DATE('%Y-%m', data_venda) AS ano_mes,
    SUM(valor) AS faturamento_total
  FROM vendas_base
  GROUP BY ano_mes
),

evolucao AS (
  SELECT
    ano_mes,
    faturamento_total,
    LAG(faturamento_total) OVER (ORDER BY ano_mes) AS faturamento_mes_anterior,
    SAFE_DIVIDE(
      faturamento_total - LAG(faturamento_total) OVER (ORDER BY ano_mes),
      LAG(faturamento_total) OVER (ORDER BY ano_mes)
    ) AS variacao_mom
  FROM faturamento_mensal
)

SELECT
  ano_mes,
  faturamento_total,
  faturamento_mes_anterior,
  variacao_mom
FROM evolucao
ORDER BY ano_mes
);


========================================

CREATE OR REPLACE TABLE `automacoes-481202.case_telecom.tbdc_contrib_faturamento` as(
WITH produtos AS (
  SELECT
    SAFE_CAST(id_produto AS INT64) AS id_produto,
    nome_produto
  FROM `automacoes-481202.case_telecom.base_produtos`
),

vendas AS (
  SELECT
    SAFE_CAST(id_produto AS INT64) AS id_produto,
    SAFE_CAST(valor AS NUMERIC) AS valor
  FROM `automacoes-481202.case_telecom.base_vendas`
  WHERE SAFE_CAST(valor AS NUMERIC) IS NOT NULL
),

vendas_produto AS (
  SELECT
    COALESCE(p.nome_produto, CONCAT('PRODUTO_ID_', CAST(v.id_produto AS STRING))) AS nome_produto,
    SUM(v.valor) AS faturamento_produto
  FROM vendas v
  LEFT JOIN produtos p
    ON p.id_produto = v.id_produto
  GROUP BY nome_produto
),

total AS (
  SELECT SUM(faturamento_produto) AS faturamento_total_periodo
  FROM vendas_produto
)

SELECT
  vp.nome_produto,
  vp.faturamento_produto,
  SAFE_DIVIDE(vp.faturamento_produto, t.faturamento_total_periodo) AS participacao_no_total,
  DENSE_RANK() OVER (ORDER BY vp.faturamento_produto DESC) AS rank_faturamento
FROM vendas_produto vp
CROSS JOIN total t
ORDER BY vp.faturamento_produto DESC
)


=====================

CREATE OR REPLACE TABLE `automacoes-481202.case_telecom.tbdc_ativos_x_cancelados` as(
WITH clientes_raw AS (
  SELECT
    nome_cliente,
    estado,
    cidade,
    vendedor,
    status
  FROM `automacoes-481202.case_telecom.base_clientes`
),

status_padronizado AS (
  SELECT
    CASE
      WHEN UPPER(TRIM(status)) IN ('ATIVO') THEN 'ATIVO'
      WHEN UPPER(TRIM(status)) IN ('CANCELADO') THEN 'CANCELADO'
      ELSE 'OUTROS'
    END AS status_final
  FROM clientes_raw
),

contagens AS (
  SELECT
    status_final,
    COUNT(*) AS qtd_clientes
  FROM status_padronizado
  GROUP BY status_final
),

total AS (
  SELECT SUM(qtd_clientes) AS total_clientes
  FROM contagens
)

SELECT
  c.status_final,
  c.qtd_clientes,
  SAFE_DIVIDE(c.qtd_clientes, t.total_clientes) AS proporcao
FROM contagens c
CROSS JOIN total t
ORDER BY c.qtd_clientes DESC
)


============


CREATE OR REPLACE TABLE `automacoes-481202.case_telecom.tbdc_cidade_estados_mais_crecimento` as(
WITH vendas_geo AS (
  SELECT
    estado,
    cidade,
    SAFE_CAST(valor AS NUMERIC) AS valor
  FROM `automacoes-481202.case_telecom.base_vendas`
  WHERE SAFE_CAST(valor AS NUMERIC) IS NOT NULL
)

SELECT
  estado,
  cidade,
  SUM(valor) AS faturamento_total
FROM vendas_geo
GROUP BY estado, cidade
ORDER BY faturamento_total DESC
)


=======================

CREATE OR REPLACE TABLE `automacoes-481202.case_telecom.tbdc_cidade_estados_mais_crecimento_por_mes` as(
WITH vendas_geo_mes AS (
  SELECT
    FORMAT_DATE('%Y-%m', SAFE_CAST(data_venda AS DATE)) AS ano_mes,
    estado,
    cidade,
    SAFE_CAST(valor AS NUMERIC) AS valor
  FROM `automacoes-481202.case_telecom.base_vendas`
  WHERE SAFE_CAST(data_venda AS DATE) IS NOT NULL
    AND SAFE_CAST(valor AS NUMERIC) IS NOT NULL
),

geo_mes AS (
  SELECT
    ano_mes,
    estado,
    cidade,
    SUM(valor) AS faturamento_mes
  FROM vendas_geo_mes
  GROUP BY ano_mes, estado, cidade
),

geo_crescimento AS (
  SELECT
    ano_mes,
    estado,
    cidade,
    faturamento_mes,
    LAG(faturamento_mes) OVER (PARTITION BY estado, cidade ORDER BY ano_mes) AS faturamento_mes_anterior,
    SAFE_DIVIDE(
      faturamento_mes - LAG(faturamento_mes) OVER (PARTITION BY estado, cidade ORDER BY ano_mes),
      LAG(faturamento_mes) OVER (PARTITION BY estado, cidade ORDER BY ano_mes)
    ) AS crescimento_mom
  FROM geo_mes
)

SELECT
  ano_mes,
  estado,
  cidade,
  faturamento_mes,
  faturamento_mes_anterior,
  crescimento_mom
FROM geo_crescimento
ORDER BY ano_mes, faturamento_mes DESC
)



===================


CREATE OR REPLACE TABLE `automacoes-481202.case_telecom.tbdc_vendas_enriquecidas` AS (
WITH geral AS (
  SELECT
    SAFE_CAST(v.id_venda AS INT64) AS id_venda,
    SAFE_CAST(v.id_produto AS INT64) AS id_produto,
    p.nome_produto,

    SAFE_CAST(v.data_venda AS DATE) AS data_venda,
    DATE_TRUNC(SAFE_CAST(v.data_venda AS DATE), MONTH) AS mes_venda,

    SAFE_CAST(v.valor AS NUMERIC) AS receita,

    v.estado,
    v.cidade,
    v.vendedor
  FROM `automacoes-481202.case_telecom.base_vendas` v
  LEFT JOIN `automacoes-481202.case_telecom.base_produtos` p
    ON SAFE_CAST(v.id_produto AS INT64) = SAFE_CAST(p.id_produto AS INT64)
  WHERE SAFE_CAST(v.data_venda AS DATE) IS NOT NULL
    AND SAFE_CAST(v.valor AS NUMERIC) IS NOT NULL
),

agregacao AS (
  SELECT
    id_venda,
    id_produto,
    COALESCE(nome_produto, CONCAT('PRODUTO_ID_', CAST(id_produto AS STRING))) AS nome_produto,
    data_venda,
    mes_venda,
    estado,
    cidade,
    vendedor,
    SUM(receita) AS receita
  FROM geral
  GROUP BY 1,2,3,4,5,6,7,8
)

SELECT * FROM agregacao
);
