using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using Spectre.Console.Cli;

using STROM.ATOM.TOOL.Common.Extensions.CommandAppExtensions;

namespace STROM.ATOM.TOOL.Common.Spectre
{

    /// <summary>
    /// A hosted service that runs the Spectre.CommandApp asynchronously.
    /// When the CommandApp finishes (or is canceled), it signals the host to stop.
    /// If an exception occurs, it sets a default exit code if the command hasn’t already done so.
    /// </summary>
    public class SpectreCommandAppHostedService : BackgroundService
    {
        private readonly CommandApp _commandApp;
        private readonly string[] _args;
        private readonly ILogger<SpectreCommandAppHostedService> _logger;
        private readonly IHostApplicationLifetime _hostApplicationLifetime;
        private readonly ExitCodeHolder _exitCodeHolder;

        public SpectreCommandAppHostedService(
            CommandApp commandApp,
            ILogger<SpectreCommandAppHostedService> logger,
            IHostApplicationLifetime hostApplicationLifetime,
            string[] args,
            ExitCodeHolder exitCodeHolder)
        {
            _commandApp = commandApp;
            _logger = logger;
            _hostApplicationLifetime = hostApplicationLifetime;
            _args = args;
            _exitCodeHolder = exitCodeHolder;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            try
            {
                _logger.LogDebug("Starting CommandApp...");
                // RunAsync uses the ambient cancellation token set via AsyncLocal.
                await _commandApp.RunAsync(_args, stoppingToken);
                _logger.LogDebug("CommandApp finished.");

                if (!_exitCodeHolder.ExitCode.HasValue)
                    _exitCodeHolder.ExitCode = 0;

                _hostApplicationLifetime.StopApplication();
            }
            catch (OperationCanceledException)
            {
                _logger.LogDebug("CommandApp execution was canceled.");
                if (!_exitCodeHolder.ExitCode.HasValue)
                    _exitCodeHolder.ExitCode = -10;
                _hostApplicationLifetime.StopApplication();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "An error occurred while running the CommandApp.");
                if (!_exitCodeHolder.ExitCode.HasValue)
                    _exitCodeHolder.ExitCode = -11;
                _hostApplicationLifetime.StopApplication();
            }
        }
    }
}
