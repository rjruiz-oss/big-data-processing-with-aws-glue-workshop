CREATE TABLE "db_rues"."ml_dataset_renovacion"
WITH (
    format = 'PARQUET',
    external_location = 's3://<S3_BUCKET>/gold/ml_dataset_renovacion/',
    write_compression = 'SNAPPY'
) AS
WITH base_join AS (
    SELECT
        d.matricula,
        d.codigo_camara,
        d.camara_comercio,
        d.tipo_sociedad,
        d.organizacion_juridica,
        d.categoria_matricula,
        d.actividad_economica,
        d.tipo_persona,
        f.estado_matricula,
        d.antiguedad_empresa,
        TRY_CAST(f.ultimo_ano_renovado AS bigint) AS ultimo_ano_renovado,
        f.fecha_vigencia,
        f.fecha_renovacion,
        f.fecha_actualizacion
    FROM "db_rues"."gold_dim_empresa" AS d
    INNER JOIN "db_rues"."gold_fact_renovacion" AS f
        ON d.matricula = f.matricula
    WHERE
        f.estado_matricula IN ('ACTIVA', 'RENOVADA', 'CANCELADA')
        AND d.antiguedad_empresa IS NOT NULL
        AND TRY_CAST(f.ultimo_ano_renovado AS bigint) IS NOT NULL
        AND d.tipo_sociedad IS NOT NULL
        AND d.actividad_economica IS NOT NULL
),

deduplicados AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY matricula
            ORDER BY fecha_actualizacion DESC
        ) AS rn
    FROM base_join
),

datos_limpios AS (
    SELECT
        matricula,
        codigo_camara,
        camara_comercio,
        tipo_sociedad,
        organizacion_juridica,
        categoria_matricula,
        actividad_economica,
        tipo_persona,
        estado_matricula,
        CAST(antiguedad_empresa AS double) AS antiguedad_empresa,
        ultimo_ano_renovado,
        YEAR(fecha_vigencia) AS ano_vigencia,
        YEAR(fecha_renovacion) AS ano_ultima_renovacion,
        YEAR(CURRENT_DATE) AS ano_actual
    FROM deduplicados
    WHERE rn = 1
),

dataset_ml AS (
    SELECT
        codigo_camara,
        camara_comercio,
        tipo_sociedad,
        organizacion_juridica,
        categoria_matricula,
        actividad_economica,
        tipo_persona,
        antiguedad_empresa,
        ultimo_ano_renovado,

        CASE
            WHEN ultimo_ano_renovado = CAST(YEAR(CURRENT_DATE) AS bigint) THEN 1
            WHEN ultimo_ano_renovado = CAST(YEAR(CURRENT_DATE) - 1 AS bigint) THEN 1
            ELSE 0
        END AS renovo,

        CASE
            WHEN antiguedad_empresa < 2 THEN 'Nueva'
            WHEN antiguedad_empresa BETWEEN 2 AND 5 THEN 'Joven'
            WHEN antiguedad_empresa BETWEEN 6 AND 10 THEN 'Establecida'
            ELSE 'Madura'
        END AS segmento_antiguedad,

        CAST(YEAR(CURRENT_DATE) AS bigint) - ultimo_ano_renovado AS anos_sin_renovar

    FROM datos_limpios
)

SELECT *
FROM dataset_ml
WHERE renovo IS NOT NULL
LIMIT 500000;
