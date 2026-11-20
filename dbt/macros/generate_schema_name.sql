{#
  By default dbt joins the profile schema and the custom schema together,
  so "+schema: silver" would create a schema called "silver_silver".
  This override tells dbt to use the custom schema name exactly as written,
  so Silver models go to "silver" and, later, Gold models go to "gold".
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
