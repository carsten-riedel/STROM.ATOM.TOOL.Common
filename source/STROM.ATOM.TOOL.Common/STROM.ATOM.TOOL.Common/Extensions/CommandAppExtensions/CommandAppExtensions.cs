using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

using Spectre.Console.Cli;

using STROM.ATOM.TOOL.Common.Spectre;

namespace STROM.ATOM.TOOL.Common.Extensions.CommandAppExtensions
{
    /// <summary>
    /// Extension methods for Spectre.Console's CommandApp.
    /// </summary>
    public static class CommandAppExtensions
    {
        /// <summary>
        /// Runs the command app asynchronously while honoring a cancellation token.
        /// The provided (linked) cancellation token is stored in an ambient context so that it flows into commands.
        /// </summary>
        public static async Task<int> RunAsync(this CommandApp commandApp, string[] args, CancellationToken cancellationToken)
        {
            // Store the cancellation token in our ambient context.
            CommandCancellationTokenContext.Token.Value = cancellationToken;

            // Start the command execution on a background thread.
            var runTask = Task.Run(() => commandApp.Run(args));

            // Create a task that completes when cancellation is requested.
            var cancelTask = Task.Delay(Timeout.Infinite, cancellationToken);

            // Wait for either the command to finish or for cancellation to trigger.
            var completedTask = await Task.WhenAny(runTask, cancelTask);
            if (completedTask == runTask)
            {
                // Command finished normally.
                return await runTask;
            }
            else
            {
                // Cancellation was requested.
                throw new OperationCanceledException(cancellationToken);
            }
        }
    }
}
