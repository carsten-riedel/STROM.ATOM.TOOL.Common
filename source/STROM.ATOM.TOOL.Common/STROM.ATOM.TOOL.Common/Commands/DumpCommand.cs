using System;
using System.ComponentModel;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.Extensions.Logging;

using Serilog.Events;

using Spectre.Console;
using Spectre.Console.Cli;

using STROM.ATOM.TOOL.Common.Services;
using STROM.ATOM.TOOL.Common.Spectre;

namespace STROM.ATOM.TOOL.Common.Commands
{
    /// <summary>
    /// A concrete abortable command that demonstrates asynchronous, cancellation-aware work.
    /// After 5 seconds it returns success (0), and if aborted it returns 99.
    /// </summary>
    public class DumpCommand : CancellableCommand<DumpCommand.Settings>
    {
        //private readonly IGreeter _greeter;
        private readonly ILogger<DumpCommand> _logger;
        private readonly IOsVersionService _osVersionService;

        private int baseErrorCode = 10;

        private bool forceSuccess = false;

        private int BaseErrorCode
        {
            get
            {
                if (forceSuccess)
                {
                    return 0;
                }
                else
                {
                    return baseErrorCode;
                }
            }
        }

        public class Settings : CommandSettings
        {
            [Description("The target to dump e.g. osversion")]
            [CommandArgument(0, "<Target>")]
            public string? Target { get; init; }

            [Description("Minimum loglevel, valid values => Verbose,Debug,Information,Warning,Error,Fatal")]
            [DefaultValue(LogEventLevel.Warning)]
            [CommandOption("-l|--loglevel")]
            public LogEventLevel LogEventLevel { get; init; }

            [Description("Throws and errorcode if command is not found.")]
            [DefaultValue(false)]
            [CommandOption("-f|--forceSuccess")]
            public bool ForceSuccess { get; init; }

            public override ValidationResult Validate()
            {
                if (String.IsNullOrWhiteSpace(Target))
                {
                    return ValidationResult.Error("Required argument <Target> cannot be empty");
                }

                return ValidationResult.Success();
            }
        }

        public DumpCommand(ILogger<DumpCommand> logger, IOsVersionService osVersionService)
        {
            _osVersionService = osVersionService ?? throw new ArgumentNullException(nameof(osVersionService));
            _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        }

        public override async Task<int> ExecuteAsync(CommandContext context, Settings settings, CancellationToken cancellationToken)
        {
            Program.levelSwitch.MinimumLevel = settings.LogEventLevel;
            forceSuccess = settings.ForceSuccess;
            _logger.LogInformation("{CommandName} command started.", context.Name);

            try
            {
                if (settings.Target!.Equals("osversion", StringComparison.OrdinalIgnoreCase))
                {
                    await _osVersionService.ShowOsVersion(cancellationToken);
                    return 0;
                }
                else
                {
                    var result = await SpectreConsole.WriteTemplateAsync("The Target: '{Target}' can not be found.", new string[] { "" }, settings.Target);
                    _logger.LogInformation(result.MessageTemplate, result.PropertyValues);
                    return BaseErrorCode + 2;
                }
            }
            catch (OperationCanceledException ex)
            {
                _logger.LogError(ex,"{CommandName} command canceled internally.", context.Name);
                return BaseErrorCode;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "{CommandName} command canceled internally.", context.Name);
                return BaseErrorCode + 1;
            }
        }
    }
}