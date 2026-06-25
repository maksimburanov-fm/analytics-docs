from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, CallbackQueryHandler, ContextTypes
from analytics import AnalyticsService

from config import TELEGRAM_BOT_TOKEN, ALLOWED_USERS


def is_allowed(user_id: int) -> bool:
    if not ALLOWED_USERS:
        return True
    return user_id in ALLOWED_USERS


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user

    if not is_allowed(user.id):
        await update.message.reply_text("У тебя нет доступа к этому боту.")
        return

    await update.message.reply_text(
        f"Привет! Бот работает.\n\n"
        f"Твой Telegram user_id: {user.id}\n\n"
        f"Команды:\n"
        f"/start — проверить бота\n"
        f"/help — список команд"
    )


async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user

    if not is_allowed(user.id):
        await update.message.reply_text("У тебя нет доступа к этому боту.")
        return

    await update.message.reply_text(
        "Доступные команды:\n"
        "/start — проверить запуск\n"
        "/help — список команд\n"
        "/tv_report — выбрать период и получить отчёт ТВ-смотрения\n"
        "/report — выбрать отчёт и параметры\n"
    )

async def sport_yesterday(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user

    if not is_allowed(user.id):
        await update.message.reply_text("У тебя нет доступа к этому боту.")
        return

    await update.message.reply_text("⏳ Запрашиваю отчёт по спортивным каналам за вчера...")

    try:
        service = AnalyticsService()
        message = service.sport_yesterday()
        await update.message.reply_text(message)
    except Exception as e:
        await update.message.reply_text(f"❌ Ошибка при получении отчёта:\n{e}")

def main():
    if not TELEGRAM_BOT_TOKEN:
        raise ValueError("Не найден TELEGRAM_BOT_TOKEN в .env")

    app = Application.builder().token(TELEGRAM_BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("help", help_command))
    app.add_handler(CommandHandler("sport_yesterday", sport_yesterday))
    app.add_handler(CommandHandler("tv_report", tv_report))
    app.add_handler(CallbackQueryHandler(handle_tv_period, pattern="^tv_period:"))
    app.add_handler(CommandHandler("report", report_menu))
    app.add_handler(CallbackQueryHandler(handle_report_choice, pattern="^report:"))
    app.add_handler(CallbackQueryHandler(handle_tv_category, pattern="^tv_category:"))

    print("Bot started. Press Ctrl+C to stop.")
    app.run_polling()

async def tv_report(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user

    if not is_allowed(user.id):
        await update.message.reply_text("У тебя нет доступа к этому боту.")
        return

    keyboard = [
        [
            InlineKeyboardButton("Вчера", callback_data="tv_period:yesterday"),
            InlineKeyboardButton("Эта неделя", callback_data="tv_period:this_week"),
        ],
        [
            InlineKeyboardButton("Прошлая неделя", callback_data="tv_period:last_week"),
            InlineKeyboardButton("Этот месяц", callback_data="tv_period:this_month"),
        ],
        [
            InlineKeyboardButton("Прошлый месяц", callback_data="tv_period:last_month"),
        ],
    ]

    await update.message.reply_text(
        "Выбери период для отчёта по ТВ-смотрению:",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )

async def handle_tv_period(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = query.from_user

    if not is_allowed(user.id):
        await query.answer("Нет доступа")
        return

    await query.answer()

    period_key = query.data.split(":")[1]

    await query.edit_message_text("⏳ Запрашиваю отчёт...")

    try:
        service = AnalyticsService()
        category = context.user_data.get("tv_category", "sport")
        message = service.tv_report(period_key=period_key, category=category)

        await query.edit_message_text(message)
    except Exception as e:
        await query.edit_message_text(f"❌ Ошибка при получении отчёта:\n{e}")
    

async def report_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user

    if not is_allowed(user.id):
        await update.message.reply_text("У тебя нет доступа к этому боту.")
        return

    keyboard = [
        [
            InlineKeyboardButton(
                "📺 ТВ-смотрение",
                callback_data="report:tv_viewing",
            )
        ],
    ]

    await update.message.reply_text(
        "Выбери отчёт:",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )
async def handle_report_choice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = query.from_user

    if not is_allowed(user.id):
        await query.answer("Нет доступа")
        return

    await query.answer()

    report_key = query.data.split(":")[1]

    if report_key == "tv_viewing":
        keyboard = [
            [
                InlineKeyboardButton("Спорт", callback_data="tv_category:sport"),
                InlineKeyboardButton("Детские", callback_data="tv_category:kids"),
            ],
            [
                InlineKeyboardButton("Все каналы", callback_data="tv_category:all"),
            ],
        ]

        await query.edit_message_text(
            "Отчёт: ТВ-смотрение\n\nВыбери категорию каналов:",
            reply_markup=InlineKeyboardMarkup(keyboard),
        )
async def handle_tv_category(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    user = query.from_user

    if not is_allowed(user.id):
        await query.answer("Нет доступа")
        return

    await query.answer()

    category = query.data.split(":")[1]
    context.user_data["tv_category"] = category

    keyboard = [
        [
            InlineKeyboardButton("Вчера", callback_data="tv_period:yesterday"),
            InlineKeyboardButton("Эта неделя", callback_data="tv_period:this_week"),
        ],
        [
            InlineKeyboardButton("Прошлая неделя", callback_data="tv_period:last_week"),
            InlineKeyboardButton("Этот месяц", callback_data="tv_period:this_month"),
        ],
        [
            InlineKeyboardButton("Прошлый месяц", callback_data="tv_period:last_month"),
        ],
    ]

    await query.edit_message_text(
        f"Категория: {category}\n\nВыбери период:",
        reply_markup=InlineKeyboardMarkup(keyboard),
    )



if __name__ == "__main__":
    main()
