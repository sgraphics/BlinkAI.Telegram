using BlinkAI.Telegram;
using Telegram.Bot;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorPages();

// Register the TelegramBotClient as a singleton
builder.Services.AddSingleton<ITelegramBotClient>(provider =>
	new TelegramBotClient(builder.Configuration["BotToken"]));

builder.Services.AddSingleton<AiProxy>();

// Register the BotHostedService
builder.Services.AddHostedService<BotHostedService>();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
	app.UseExceptionHandler("/Error");
	// The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
	app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapRazorPages();

// Optional: Map a default route to respond to web requests
app.MapGet("/", () => "Bot is running.");

app.Run();
