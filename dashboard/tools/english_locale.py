"""Translate display text without changing stored demo data or stable identifiers.

The JSON dictionary intentionally retains exact legacy Russian strings as lookup
keys. CI_NAMES, INCIDENT_TITLES, METRIC_NAMES and STATUS_REASONS are source-value
allowlists, not untranslated documentation. Matching is literal and longest-first
so a short phrase cannot consume the prefix of a more specific phrase.

english_values recursively translates string values in report JSON while keeping
object keys intact. fit_english_filters adjusts only known widget geometry for
longer English labels. english_sql supplies read-only localized projection CTEs
for ci, incident and metric_definition, rewriting references in generated SQL.
This is controlled source generation, not a general SQL parser or a migration:
keep its exact replacement anchors synchronized with the query builders.
"""

from pathlib import Path
import json, re

TRANSLATIONS = json.loads(Path(__file__).with_name("en_translations.json").read_text())
_PATTERN = re.compile(
    "|".join(re.escape(s) for s in sorted(TRANSLATIONS, key=len, reverse=True))
)


def english_text(text):
    """Translate known literal substrings; leave unmatched text and codes unchanged."""
    return _PATTERN.sub(lambda match: TRANSLATIONS[match.group()], text)


def english_values(value):
    """Return a recursively localized copy of JSON-like values.

    Dictionaries preserve keys; numbers, booleans and null remain unchanged. This
    deliberately does not rename dataset fields, widget identifiers or parameters."""
    if isinstance(value, str):
        return english_text(value)
    if isinstance(value, list):
        return [english_values(item) for item in value]
    if isinstance(value, dict):
        return {key: english_values(item) for key, item in value.items()}
    return value


def fit_english_filters(store):
    """Adjust known filter x/width values in the mutable FineVIS story store.

    English environment/software labels need more room on compact IT, Issues and
    History layouts. Matrix index 4 is horizontal translation; other transforms,
    widget IDs and report behavior remain untouched."""
    for page in store["stories"]:
        if page["name"] in ("Issues", "History"):
            positions = {
                "scene_p_env": (656, 190),
                "scene_p_env label": (656, 190),
                "scene_p_software": (862, 270),
                "scene_p_software label": (862, 270),
            }
        elif page["name"] == "IT · servers":
            positions = {
                "p_env": (646, 190),
                "Environment": (646, 190),
                "p_software": (850, 235),
                "Software": (850, 235),
            }
        else:
            continue
        for widget in page["widgets"]:
            if widget["name"] in positions:
                x, width = positions[widget["name"]]
                widget["states"]["matrix"][4] = x
                widget["states"]["width"] = width


def literal(text):
    """Quote a trusted display literal for SQL, escaping embedded apostrophes.

    This is for generated lookup CASE expressions, never arbitrary SQL fragments."""
    return "'" + text.replace("'", "''") + "'"


def display_case(expression, keys):
    """Build a display-only CASE that falls back to the original source expression.

    Unknown fixture text remains visible rather than becoming null; keys are
    exact source strings and all result literals are safely apostrophe-escaped."""
    return (
        "CASE "
        + expression
        + " "
        + " ".join(
            "WHEN " + literal(key) + " THEN " + literal(english_text(key))
            for key in keys
        )
        + " ELSE "
        + expression
        + " END"
    )


CI_NAMES = [
    "Автоматизированная банковская система",
    "Дистанционное банковское обслуживание",
    "Кадровая система",
    "Мониторинг инфраструктуры",
    "Управление отношениями с клиентами",
    "Хранилище данных",
]
CI_NAMES += ["ЦОД «" + site + "»" for site in ["Север", "Восток", "Резерв"]]
CI_NAMES += [
    "Зал " + hall + " · " + site
    for hall in ["A", "B"]
    for site in ["Север", "Восток", "Резерв"]
]
INCIDENT_TITLES = [
    "CRAC-02: снижена холодопроизводительность; температура R12 29,4 °C",
    "Кратковременная потеря связи",
]
METRIC_NAMES = [
    "Загрузка CPU",
    "Занятость IO",
    "Температура диска",
    "Ёмкость диска",
    "Задержка диска",
    "Чтение: IOPS",
    "Скорость чтения",
    "Ошибки SMART",
    "Занято на диске",
    "Диск: занято",
    "Запись: IOPS",
    "Скорость записи",
    "Скорость вентилятора",
    "Влажность",
    "Температура на входе",
    "Занято RAM",
    "Потери в секунду",
    "Ошибки в секунду",
    "Состояние порта",
    "Приём",
    "Передача",
    "Загрузка порта",
    "Принятые байты",
    "Активная мощность",
    "Занято дисковое пространство",
    "Температура коммутатора",
]
STATUS_REASONS = [
    "Демо: HDD /data — 97%, 58 °C, задержка 42 мс",
    "Демонстрационное штатное состояние",
    "Нет наблюдения",
    "Демо: port-1 — 92%, ошибки и потери пакетов",
    "Нет телеметрии",
    "Высокая температура / снижена холодопроизводительность",
]


def english_sql(sql):
    """Localize a complete read-only SQL statement while preserving its contract.

    Known reason/model projections are rewritten first. Table references are then
    redirected to materialized localized projections only when used. New CTEs
    preserve WITH RECURSIVE when present or introduce WITH for lookup queries.
    All exposed columns, IDs, metric/state codes, units and underlying rows remain
    unchanged. This function performs no database writes."""
    sql = english_text(sql)
    sql = sql.replace(
        "\n dev.model,dev.cpu_cores",
        "\n replace(dev.model,' диска',' drives') AS model,dev.cpu_cores",
    )
    sql = sql.replace(
        "st.reason,st.observed_at",
        display_case("st.reason", STATUS_REASONS) + " AS reason,st.observed_at",
    )
    name = display_case("name", CI_NAMES)
    name = (
        "CASE WHEN name LIKE 'Стойка %' THEN 'Rack '||substr(name,8) ELSE "
        + name
        + " END"
    )
    definitions = {
        "ci": f"SELECT ci_id,ci_key,kind,{name} AS name,owner_team_id,lifecycle,retired_at,first_seen_at,last_seen_at FROM dcmon.ci",
        "incident": "SELECT id,incident_key,source_id,external_id,"
        + display_case("title", INCIDENT_TITLES)
        + " AS title,severity,detected_at,owner_team_id,response_due_at FROM dcmon.incident",
        "metric_definition": "SELECT id,code,"
        + display_case("name", METRIC_NAMES)
        + " AS name,unit,metric_type,valid_min,valid_max,warning_above,critical_above FROM dcmon.metric_definition",
    }
    ctes = []
    for table, body in definitions.items():
        sql, count = re.subn(r"\bdcmon\." + table + r"\b", "localized_" + table, sql)
        if count:
            ctes.append("localized_" + table + " AS MATERIALIZED (" + body + ")")
    if not ctes:
        return sql
    prefix = ",\n".join(ctes)
    # Shared queries may start with maintainer comments. Skip that leading trivia
    # when finding WITH, while preserving it verbatim in the result. Otherwise a
    # documented recursive query would incorrectly receive a second WITH clause.
    # Only generated source SQL is accepted here; this is not a general parser.
    match = re.match(r"(?:\s+|--[^\n]*(?:\n|$)|/\*[\s\S]*?\*/)*WITH\s+(RECURSIVE\s+)?", sql, re.I)
    if match:
        return sql[: match.end()] + prefix + ",\n" + sql[match.end() :]
    return "WITH " + prefix + "\n" + sql
