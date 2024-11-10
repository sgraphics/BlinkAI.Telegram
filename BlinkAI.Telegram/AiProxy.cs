using System.Text;
using System.Text.Json;
using Azure;
using Azure.AI.OpenAI;
using Azure.Core;
using Flurl;
using Flurl.Http;
using Microsoft.OpenApi.Models;
using Microsoft.OpenApi.Readers;

namespace BlinkAI.Telegram
{
	public class DallEData
	{
		public string url { get; set; }
	}
	public class DallEResponse
	{
		public IList<DallEData> data { get; set; }
	}
	public class AiProxy
	{
		private readonly IConfiguration _configuration;
		private readonly ILogger<AiProxy> _log;

		public AiProxy(IConfiguration configuration, ILogger<AiProxy> log)
		{
			_configuration = configuration;
			_log = log;
		}

		public async Task<string> Think(IList<ChatRequestMessage> messages)
		{
			var api = Think(messages, out var completionRequest);
			var result = await api.GetChatCompletionsStreamingAsync(completionRequest);
			var output = result.ToString();
			return output;
		}

		public async Task<string> GenerateImage(string prompt, string style, string size)
		{
			var apiKey = _configuration["DallEKey"];

			var api = new OpenAIClient(
				new Uri("https://stock-photo.openai.azure.com/openai/deployments/stock-photo/images/generations?api-version=2023-12-01-preview"),
				new AzureKeyCredential(apiKey));
			string retData = null;
			Exception lastException = null;
			for (int i = 0; i < 4; i++)
			{
				try
				{
					var response = await "https://stock-photo.openai.azure.com/openai/deployments/stock-photo/images/generations?api-version=2023-12-01-preview"
						.WithHeader("api-key", apiKey)
						.PostJsonAsync(new
						{
							prompt,
							size,
							n = 1,
							quality = "hd",
							style
						})
						.ReceiveJson<DallEResponse>();


					return response.data[0].url;
					//Response<ImageGenerations> imageGenerations = await api.GetImageGenerationsAsync(
					//	new ImageGenerationOptions()
					//	{
					//		ImageCount = 1,
					//		Prompt = prompt,
					//		Size = new ImageSize(size),

					//	});

					//// Image Generations responses provide URLs you can use to retrieve requested images
					//return imageGenerations.Value.Data[0].Url.ToString();
				}
				catch (FlurlHttpException ex)
				{
					lastException = ex;
					_log.LogError(ex, "Generation failed");
				}
			}

			throw lastException;
		}

		public async IAsyncEnumerable<string> ThinkStream(IList<ChatRequestMessage> messages, Gpt gpt)
		{
			var api = Think(messages, out var completionRequest);

			var openApiSpecUrl = "https://www.blinkai.xyz/api/gpt/getschema";
			var openApiDocument = await GetOpenApiDocument(openApiSpecUrl);

			//var (tools, operationToRouteMap) = GenerateFunctionToolDefinitions(openApiDocument);

			var tools = GetChatCompletionsFunctionToolDefinitions(openApiDocument, out var operationToRouteMap);

			foreach (var tool in tools)
			{
				completionRequest.Tools.Add(tool);

			}

			Dictionary<int, string> toolCallIdsByIndex = new();
			Dictionary<int, string> functionNamesByIndex = new();
			Dictionary<int, StringBuilder> functionArgumentBuildersByIndex = new();
			StringBuilder contentBuilder = new();

			await foreach (StreamingChatCompletionsUpdate chatUpdate
						   in await api.GetChatCompletionsStreamingAsync(completionRequest))
			{
				if (chatUpdate.ToolCallUpdate is StreamingFunctionToolCallUpdate functionToolCallUpdate)
				{
					if (functionToolCallUpdate.Id != null)
					{
						toolCallIdsByIndex[functionToolCallUpdate.ToolCallIndex] = functionToolCallUpdate.Id;
					}
					if (functionToolCallUpdate.Name != null)
					{
						functionNamesByIndex[functionToolCallUpdate.ToolCallIndex] = functionToolCallUpdate.Name;
					}
					if (functionToolCallUpdate.ArgumentsUpdate != null)
					{
						StringBuilder argumentsBuilder
							= functionArgumentBuildersByIndex.TryGetValue(
								functionToolCallUpdate.ToolCallIndex,
								out StringBuilder existingBuilder) ? existingBuilder : new StringBuilder();
						argumentsBuilder.Append(functionToolCallUpdate.ArgumentsUpdate);
						functionArgumentBuildersByIndex[functionToolCallUpdate.ToolCallIndex] = argumentsBuilder;
					}
				}

				var chatUpdateContentUpdate = chatUpdate.ContentUpdate;

				if (chatUpdateContentUpdate != null)
				{
					yield return chatUpdateContentUpdate;
					contentBuilder.Append(chatUpdateContentUpdate);
				}
			}

			ChatRequestAssistantMessage assistantHistoryMessage = new(contentBuilder.ToString());
			foreach (var indexIdPair in toolCallIdsByIndex)
			{
				assistantHistoryMessage.ToolCalls.Add(new ChatCompletionsFunctionToolCall(
					id: indexIdPair.Value,
					functionNamesByIndex[indexIdPair.Key],
					functionArgumentBuildersByIndex[indexIdPair.Key].ToString()));
			}
			messages.Add(assistantHistoryMessage);

			if (toolCallIdsByIndex.Any())
			{
				var client = new NodeJsApiClient(_configuration["API"]);

				foreach (var indexIdPair in toolCallIdsByIndex)
				{
					var functionName = functionNamesByIndex[indexIdPair.Key];
					var argumentsJson = functionArgumentBuildersByIndex[indexIdPair.Key].ToString();
					var arguments = JsonSerializer.Deserialize<Dictionary<string, object>>(argumentsJson);

					if (operationToRouteMap.TryGetValue(functionName, out var routeAndMethod))
					{
						var (route, method) = routeAndMethod;
						try
						{
							var apiResponse = await client.CallApiAsync(route.TrimStart('/'), method, arguments, gpt);
							messages.Add(new ChatRequestToolMessage(apiResponse, indexIdPair.Value));
						}
						catch (Exception ex)
						{
							messages.Add(new ChatRequestToolMessage(ex.Message, indexIdPair.Value));
							throw;
						}
					}
				}

				await foreach (var x in ThinkStream(messages, gpt))
				{
					yield return x;
				}
			}
		}
		private static (List<ChatCompletionsFunctionToolDefinition> tools, Dictionary<string, (string route, string method, Dictionary<string, string> paramLocations)> operationToRouteMap) OldGenerateFunctionToolDefinitions(OpenApiDocument openApiDocument)
		{
			var tools = new List<ChatCompletionsFunctionToolDefinition>();
			var operationToRouteMap = new Dictionary<string, (string route, string method, Dictionary<string, string> paramLocations)>();

			foreach (var path in openApiDocument.Paths)
			{
				foreach (var operation in path.Value.Operations)
				{
					var parameters = operation.Value.Parameters.ToDictionary(
						p => p.Name,
						p => new { type = p.Schema.Type, location = p.In.ToString() }
					);

					var paramLocations = parameters.ToDictionary(p => p.Key, p => p.Value.location);

					var parametersSchema = new
					{
						type = "object",
						properties = parameters.ToDictionary(p => p.Key, p => new { type = p.Value.type })
					};

					var parametersJson = JsonSerializer.Serialize(parametersSchema);

					var tool = new ChatCompletionsFunctionToolDefinition
					{
						Name = operation.Value.OperationId,
						Description = operation.Value.Summary,
						Parameters = BinaryData.FromString(parametersJson)
					};

					tools.Add(tool);
					operationToRouteMap[operation.Value.OperationId] = (path.Key, operation.Key.ToString(), paramLocations);
				}
			}

			return (tools, operationToRouteMap);
		}


		public static List<ChatCompletionsFunctionToolDefinition> GetChatCompletionsFunctionToolDefinitions(OpenApiDocument openApiDocument, out Dictionary<string, (string route, string method)> operationToRouteMap)
		{
			var functionDefinitions = new List<ChatCompletionsFunctionToolDefinition>();
			operationToRouteMap = new();
			foreach (var path in openApiDocument.Paths)
			{
				foreach (var operation in path.Value.Operations)
				{
					operationToRouteMap[operation.Value.OperationId] = (path.Key, operation.Key.ToString());
					var operationId = operation.Value.OperationId;
					var summary = operation.Value.Summary;
					var parameters = new Dictionary<string, object>();

					foreach (var parameter in operation.Value.Parameters)
					{
						parameters[parameter.Name] = ResolveSchema(parameter.Schema, openApiDocument.Components.Schemas);
					}

					if (operation.Value.RequestBody != null)
					{
						var requestBodySchema = operation.Value.RequestBody.Content["application/json"].Schema;
						parameters["requestBody"] = ResolveSchema(requestBodySchema, openApiDocument.Components.Schemas);
					}

					var parametersJson = JsonSerializer.Serialize(new
					{
						type = "object",
						properties = parameters,
						required = operation.Value.Parameters.Where(p => p.Required).Select(p => p.Name).ToArray()
					});

					functionDefinitions.Add(new ChatCompletionsFunctionToolDefinition
					{
						Name = operationId,
						Description = summary,
						Parameters = BinaryData.FromString(parametersJson)
					});
				}
			}

			return functionDefinitions;
		}


		private static object ResolveSchema(OpenApiSchema schema, IDictionary<string, OpenApiSchema> schemas)
		{
			//if (schema.Reference != null && schemas.TryGetValue(schema.Reference.Id, out var referencedSchema))
			//{
			//	return ResolveSchema(referencedSchema, schemas);
			//}

			var result = new Dictionary<string, object>
			{
				{ "type", schema.Type }
			};

			if (schema.Properties != null && schema.Properties.Any())
			{
				var properties = new Dictionary<string, object>();
				foreach (var property in schema.Properties)
				{
					properties[property.Key] = ResolveSchema(property.Value, schemas);
				}
				result["properties"] = properties;
			}

			if (schema.Items != null)
			{
				result["items"] = ResolveSchema(schema.Items, schemas);
			}

			return result;
		}



		private static async Task<OpenApiDocument> GetOpenApiDocument(string url)
		{
			using (var httpClient = new HttpClient())
			{
				var stream = await httpClient.GetStreamAsync(url);
				var openApiDocument = new OpenApiStreamReader().Read(stream, out var diagnostic);
				return openApiDocument;
			}
		}

		private OpenAIClient Think(IList<ChatRequestMessage> messages, out ChatCompletionsOptions completionRequest)
		{
			var apiKey = _configuration["OpenAiKey"];

			var api = new OpenAIClient(
				new Uri("https://toolblox-east-ai.openai.azure.com/"),
				new AzureKeyCredential(apiKey),
				new OpenAIClientOptions
				{
					Retry = { Delay = TimeSpan.FromMilliseconds(500), Mode = RetryMode.Exponential, MaxRetries = 5 },
				});


			completionRequest = new ChatCompletionsOptions("toolblox-gpt4o", messages)
			{
				Temperature = 0.7f,
				MaxTokens = 2000,
				FrequencyPenalty = 0.1f,
				PresencePenalty = 0,
			};
			return api;
		}
	}
	public class NodeJsApiClient
	{
		private readonly string _baseUrl;

		public NodeJsApiClient(string baseUrl)
		{
			_baseUrl = baseUrl;
		}

		public async Task<string> CallApiAsync(string route, string method, Dictionary<string, object> parameters, Gpt gpt)
		{
			if (method.Equals("GET", StringComparison.OrdinalIgnoreCase))
			{
				var queryParams = parameters.ToDictionary(p => p.Key, p => p.Value);
				var response = await $"{_baseUrl}/{route}"
					.SetQueryParams(queryParams)
					.WithOAuthBearerToken(gpt.RowKey)
					.WithHeader("openai-gpt-id", gpt.Url)
					.WithHeader("network", "BinanceTestnet")
					.GetJsonAsync<dynamic>();
				return JsonSerializer.Serialize(response);
			}
			else if (method.Equals("POST", StringComparison.OrdinalIgnoreCase))
			{
				var bodyParams = parameters.Where(p => p.Key == "requestBody").Select(p => p.Value).FirstOrDefault();
				var queryParams = parameters.Where(p => p.Key != "requestBody").ToDictionary(p => p.Key, p => p.Value);
				var response = await $"{_baseUrl}/{route}"
					.SetQueryParams(queryParams)
					.WithOAuthBearerToken(gpt.RowKey)
					.WithHeader("openai-gpt-id", gpt.Url)
					.WithHeader("network", "BinanceTestnet")
					.PostJsonAsync(bodyParams)
					.ReceiveJson<dynamic>();
				return JsonSerializer.Serialize(response);
			}
			throw new NotImplementedException($"HTTP method '{method}' is not implemented.");
		}
	}

}
