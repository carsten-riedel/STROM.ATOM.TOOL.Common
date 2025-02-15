using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

using Spectre.Console.Cli;

using STROM.ATOM.TOOL.Common.Extensions.SpectreHostExtensions;

namespace STROM.ATOM.TOOL.Common.Spectre
{
    /// <summary>
    /// An abstract base class for commands designed to be abortable via cancellation.
    /// Inherits from Spectre.Console.Cli's Command<TSettings> and overrides Execute to call the async version.
    /// This version obtains the shared ExitCodeHolder from SpectreHostExtensions.
    /// </summary>
    public abstract class AbortableCommand<TSettings> : Command<TSettings> where TSettings : CommandSettings, new()
    {
        // Instead of injecting the ExitCodeHolder via the constructor,
        // we retrieve the shared instance from SpectreHostExtensions.
        protected ExitCodeHolder _exitCodeHolder => SpectreHostExtensions.exitCodeHolder;

        public override int Execute(CommandContext context, TSettings settings)
        {
            // Retrieve the ambient cancellation token that was set by RunAsync.
            var token = CommandCancellationTokenContext.Token.Value;
            int exitCode = ExecuteAsync(context, settings, token).GetAwaiter().GetResult();
            if (!_exitCodeHolder.ExitCode.HasValue)
                _exitCodeHolder.ExitCode = exitCode;
            return exitCode;
        }

        public abstract Task<int> ExecuteAsync(CommandContext context, TSettings settings, CancellationToken cancellationToken);
    }
}
