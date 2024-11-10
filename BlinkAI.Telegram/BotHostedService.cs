using System.Collections.Concurrent;
using System.Reactive.Linq;
using System.Reactive.Subjects;
using System.Text;
using System.Text.RegularExpressions;
using Azure.AI.OpenAI;
using Telegram.Bot;
using Telegram.Bot.Polling;
using Telegram.Bot.Types;
using Telegram.Bot.Types.Enums;
using Telegram.Bot.Types.ReplyMarkups;
using static System.Net.Mime.MediaTypeNames;

namespace BlinkAI.Telegram;

public class BotHostedService : BackgroundService
{
	private readonly AiProxy _aiProxy;

	private record Message(string Text, DateTimeOffset Timestamp, string Id, bool IsHuman, bool IsChat, bool IsError = false, string? img = null)
	{
		public string? State { get; set; }
	}

	private ConcurrentDictionary<long, (SortedList<DateTimeOffset, Message> history, IList<ChatRequestMessage> internalHistory, Subject<string> currentChat, StringBuilder currentMessage)> _data = new();

	private readonly ITelegramBotClient _botClient;
	private readonly Gpt _gpt;

	public BotHostedService(ITelegramBotClient botClient, AiProxy aiProxy)
	{
		_aiProxy = aiProxy;
		_botClient = botClient;
		_gpt = new Gpt
		{
			RowKey = "ec33bdf3-a15b-4062-afda-04ea7562f3b8",
			Address = "0x7a542eebbcc66adbaa8c4b6c8eda4eb11ff5f424",
			ContractsData = "[{\"Name\":\"blinkai_rental_contract\",\"CanExecute\":true,\"CanPrepare\":true},{\"Name\":\"blinkai_auction_workflow\",\"CanExecute\":true,\"CanPrepare\":true},{\"Name\":\"blinkai_nft_flow_simple\",\"CanExecute\":true,\"CanPrepare\":true},{\"Name\":\"blinkai_chartity_and_donation\",\"CanExecute\":true,\"CanPrepare\":true},{\"Name\":\"blinkai_escrow_contract\",\"CanExecute\":true,\"CanPrepare\":true},{\"Name\":\"blinkai_fund_transfer\",\"CanExecute\":true,\"CanPrepare\":true}]",
			Key = "18d65db2ec8c097b3c9876452c2ffb238d23a617b22810a49e7c642cfd3f3fb1",
			Name = "My super assistant",
			Url = "https://chatgpt.com/g/g-djTbLhSz0-my-super-assistant"
		};
	}

	protected override async Task ExecuteAsync(CancellationToken stoppingToken)
	{
		_botClient.StartReceiving(
			new DefaultUpdateHandler(HandleUpdateAsync, HandleErrorAsync),
			cancellationToken: stoppingToken
		);

		var me = await _botClient.GetMe(stoppingToken);
		Console.WriteLine($"Start listening for @{me.Username}");
	}

	async Task HandleErrorAsync(ITelegramBotClient botClient, Exception exception, CancellationToken cancellationToken)
	{
		Console.WriteLine(exception);
	}


	private async Task<string?> SendMessage(long chatId, string? message)
	{
		var (messageHistory, records, _, _) = _data[chatId];
		try
		{
			if (string.IsNullOrWhiteSpace(message))
			{
				return null;
			}

			var newChat = message;

			messageHistory.Add(DateTimeOffset.Now, new Message(message, DateTimeOffset.Now, Guid.NewGuid().ToString(), true, true));

			var isPrompt = false;
			var prompt = string.Empty;
			int i = 10;

			if (!records.Any())
			{
				records.Add(new ChatRequestSystemMessage(@"You are an assistant called Blink Wallet - product of BlinkAI - trying to help the user. Use the tools method GetPossibleSmartContractCalls to know which blockchain actions are available.
Try to fulfill user requests as best as possible based on capabilities returned from GetPossibleSmartContractCalls.
If some transactions require the user or owner wallet address then ask the user for one.
IMPORTANT Use only simple markdown in your responses. Do not use nested lists or anything else incompatible with Telegram Bots markdown support.
IMPORTANT Try to fill all method parameters - use information given by the user if available, otherwise make best guess. For example DO NOT ask for Name or Description but make best guess.
Short Description of Blink:
* Blink - or blockchain link for AI - gives a crypto wallet for AI in the form of an AI API. AI can use the Blink API to prepare transactions for the user, execute blockchain transactions itself or query data from blockchain.
* Blink has a utility token called BLINK token which is used to enable developers purchase API quota and capabilities. In the second phase it will be also used for end-user engagement.
* The Blink button is the interface which users will see when interacting with AI. For example when the user wishes to mint an NFT or start an auction or rent something out then Blink Wallet will prepare the transaction and display a button ""Execute Transaction"". The aim is to make it as powerful as the PayPal button was 20 years ago - it aims to be an easy and secure way for individuals and businesses to handle blockchain transactions with the help of AI.	
	"));
			}

			records.Add(new ChatRequestUserMessage(@$"{newChat}"));

			var writeOut = string.Empty;

			await foreach (var item in _aiProxy.ThinkStream(records, _gpt))
			{
				if (item == null)
				{
					continue;
				}

				if (item.Trim() == "▒")
				{
					isPrompt = true;
				}
				else if (isPrompt)
				{
					prompt += item;
				}
				else
				{
					writeOut += item;
				}
			}

			string? img = null;

			messageHistory.Add(DateTimeOffset.Now, new Message(writeOut ?? string.Empty, DateTimeOffset.Now, Guid.NewGuid().ToString(), false, true, img: img));
			return writeOut ?? string.Empty;
		}
		catch (Exception ex)
		{
			messageHistory.Add(DateTimeOffset.Now, new Message(ex.Message, DateTimeOffset.Now, Guid.NewGuid().ToString(), false, false, true));
			return ex.Message;
		}
	}


	async Task HandleUpdateAsync(ITelegramBotClient botClient, Update update, CancellationToken cancellationToken)
	{
		if (update is { Type: UpdateType.Message, Message: not null })
		{
			var message = update.Message;

			var data = _data.GetOrAdd(message.Chat.Id, _ => (new SortedList<DateTimeOffset, Message>(), new List<ChatRequestMessage>(), new Subject<string>(), new StringBuilder()));

			if (message.Text == "/start")
			{
				await botClient.SendMessage(chatId: message.Chat.Id,
					text: "Just a second, fetching the capabilities list",
					cancellationToken: cancellationToken);

				var switched = data.Item3
					.Select(param => Observable.FromAsync(() => SendMessage(message.Chat.Id, param)))
					.Switch();

				//Dont care about idisposable??
				_ = switched.Subscribe(async x =>
				{
					IReplyMarkup reply = null;
					var pattern = @"https:\/\/www\.blinkai\.xyz\/gpt\/tran_(execute|open)\.svg\)\]\(https:\/\/www\.blinkai\.xyz\/transaction\/([a-f0-9-]+)\)";

					var messageToDisplay = x;

					var match = Regex.Match(x, pattern);

					if (match.Success)
					{
						var buttonType = match.Groups[1].Value;
						var transactionId = match.Groups[2].Value;

						messageToDisplay = Regex.Replace(messageToDisplay, pattern, string.Empty);

						reply = new InlineKeyboardMarkup(new[]
						{
							new[]
							{
								InlineKeyboardButton.WithWebApp(
									buttonType == "open" ? "Open transaction" : "Execute transaction",
									"https://www.blinkai.xyz/tran/" + transactionId
								)
							}
						});
					}
					await botClient.SendMessage(
						chatId: message.Chat.Id,
						text: messageToDisplay,
						parseMode: ParseMode.Markdown,
						replyMarkup: reply,
						cancellationToken: cancellationToken
					);
				});

				data.Item3.OnNext("What are your smart-contract capabilities?");
			}
			else if (!string.IsNullOrWhiteSpace(message.Text))
			{
				data.Item3.OnNext(message.Text);
			}
		}
		else if (update is { Type: UpdateType.CallbackQuery, CallbackQuery: not null })
		{
			var callbackQuery = update.CallbackQuery;
			await botClient.SendMessage(
				chatId: callbackQuery.Message.Chat.Id,
				text: $"User {callbackQuery.From.Username} clicked on {callbackQuery.Data}",
				cancellationToken: cancellationToken
			);
		}
	}
}