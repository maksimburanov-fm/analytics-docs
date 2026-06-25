from datetime import date, timedelta


def get_period(period_key: str) -> tuple[str, str, str]:
    today = date.today()

    if period_key == "yesterday":
        target = today - timedelta(days=1)
        return (
            target.strftime("%Y-%m-%d"),
            target.strftime("%Y-%m-%d"),
            "вчера",
        )

    if period_key == "this_week":
        start = today - timedelta(days=today.weekday())
        end = today
        return (
            start.strftime("%Y-%m-%d"),
            end.strftime("%Y-%m-%d"),
            "эта неделя",
        )

    if period_key == "last_week":
        this_week_start = today - timedelta(days=today.weekday())
        start = this_week_start - timedelta(days=7)
        end = this_week_start - timedelta(days=1)
        return (
            start.strftime("%Y-%m-%d"),
            end.strftime("%Y-%m-%d"),
            "прошлая неделя",
        )

    if period_key == "this_month":
        start = today.replace(day=1)
        end = today
        return (
            start.strftime("%Y-%m-%d"),
            end.strftime("%Y-%m-%d"),
            "этот месяц",
        )

    if period_key == "last_month":
        this_month_start = today.replace(day=1)
        last_month_end = this_month_start - timedelta(days=1)
        last_month_start = last_month_end.replace(day=1)
        return (
            last_month_start.strftime("%Y-%m-%d"),
            last_month_end.strftime("%Y-%m-%d"),
            "прошлый месяц",
        )

    raise ValueError(f"Неизвестный период: {period_key}")