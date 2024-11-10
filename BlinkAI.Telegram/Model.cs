using Azure;
using System.ComponentModel.DataAnnotations;
using Azure.Data.Tables;

namespace BlinkAI.Telegram
{
	public class SmartContract
	{
		/// <summary>
		/// Unique name for the smart contract
		/// </summary>
		public string Name { get; set; }
		/// <summary>
		/// Says if the GPT is allowed to execute or can just prepare the transaction
		/// </summary>
		public bool CanExecute { get; set; }
		public bool CanPrepare { get; set; }
	}

	public class Gpt
	{
		public string RowKey { get; set; } = Guid.NewGuid().ToString();
		/// <summary>
		/// Unique name of GPT
		/// </summary>
		[Required]
		public string Name { get; set; }

		/// <summary>
		/// Contracts that the GPT is able to execute or prepare executions for.
		/// </summary>
		public IList<SmartContract> Contracts { get; set; }

		public string ContractsData
		{
			get => System.Text.Json.JsonSerializer.Serialize(Contracts);
			set =>
				Contracts = string.IsNullOrWhiteSpace(value)
					? new List<SmartContract>()
					: System.Text.Json.JsonSerializer.Deserialize<IList<SmartContract>>(value);
		}

		/// <summary>
		/// GPT url in OpenAI
		/// </summary>
		public string Url { get; set; }
		public string Address { get; set; }
		public string Key { get; set; }

		public Gpt()
		{
			Contracts = new List<SmartContract>();
			RowKey = Guid.NewGuid().ToString();
		}
	}

}
