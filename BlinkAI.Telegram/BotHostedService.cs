using Telegram.Bot;
using Telegram.Bot.Polling;
using Telegram.Bot.Types;
using Telegram.Bot.Types.Enums;
using Telegram.Bot.Types.ReplyMarkups;

namespace BlinkAI.Telegram;

public class BotHostedService : BackgroundService
{
	private readonly ITelegramBotClient _botClient;

	public BotHostedService(ITelegramBotClient botClient)
	{
		_botClient = botClient;
	}

	protected override async Task ExecuteAsync(CancellationToken stoppingToken)
	{
		_botClient.StartReceiving(
			new DefaultUpdateHandler(HandleUpdateAsync, HandleErrorAsync),
			cancellationToken: stoppingToken
		);

		var me = await _botClient.GetMeAsync(stoppingToken);
		Console.WriteLine($"Start listening for @{me.Username}");
	}

	async Task HandleErrorAsync(ITelegramBotClient botClient, Exception exception, CancellationToken cancellationToken)
	{
		Console.WriteLine(exception);
	}

	async Task HandleUpdateAsync(ITelegramBotClient botClient, Update update, CancellationToken cancellationToken)
	{
		if (update.Type == UpdateType.Message && update.Message is not null)
		{
			var message = update.Message;

			if (message.Text == "/start")
			{
				await botClient.SendMessage(
					chatId: message.Chat.Id,
					text: "Welcome! Pick one direction",
					replyMarkup: new InlineKeyboardMarkup(new[]
					{
						new[]
						{
							InlineKeyboardButton.WithCallbackData("Test 1", "test1"),
							InlineKeyboardButton.WithCallbackData("Test 2", "test2")
						}
					}),
					cancellationToken: cancellationToken
				);
			}
		}
		else if (update.Type == UpdateType.CallbackQuery && update.CallbackQuery is not null)
		{
			var callbackQuery = update.CallbackQuery;
			await botClient.AnswerCallbackQuery(
				callbackQuery.Id,
				$"You picked {callbackQuery.Data}",
				cancellationToken: cancellationToken
			);

			await botClient.SendMessage(
				chatId: callbackQuery.Message.Chat.Id,
				text: $"User {callbackQuery.From.Username} clicked on {callbackQuery.Data}",
				cancellationToken: cancellationToken
			);

			await botClient.SendMessage(
				chatId: callbackQuery.Message.Chat.Id,
				text: "Hello, World!",
				replyMarkup: new InlineKeyboardMarkup(
					InlineKeyboardButton.WithWebApp(
						"Open WebApp",
						"https://www.blinkai.xyz/transaction/6936ce6d-4fbb-4416-adf9-83d5863dd804"
					)
				),
				cancellationToken: cancellationToken
			);
		}
	}
}