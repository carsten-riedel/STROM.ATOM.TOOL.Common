using System.Threading.Tasks;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using Serilog;
using Serilog.Core;
using Serilog.Events;

using Spectre.Console.Cli;

using STROM.ATOM.TOOL.Common.Commands;
using STROM.ATOM.TOOL.Common.Extensions.SpectreHostExtensions;
using STROM.ATOM.TOOL.Common.Serilog;
using STROM.ATOM.TOOL.Common.Services;
using STROM.ATOM.TOOL.Common.Spectre;

namespace STROM.ATOM.TOOL.Common
{
    public class Program
    {

        public static LoggingLevelSwitch levelSwitch = new LoggingLevelSwitch(LogEventLevel.Verbose);

        public static async Task<int> Main(string[] args)
        {

            levelSwitch.MinimumLevel = LogEventLevel.Warning;

            var loggconfig = new LoggerConfiguration()
                .MinimumLevel.ControlledBy(levelSwitch)
                .Enrich.FromLogContext()
                .WriteTo.Console(theme: Theme.ClarionDusk)
                .CreateLogger();

            Log.Logger = loggconfig;

            // Build the host.
            var host = Host.CreateDefaultBuilder(args)
                .ConfigureServices((context, services) =>
                {
                    // Register shared services.
                    services.AddSingleton<IOsVersionService, OsVersionService>();
                })
                .AddCommandAppHostedService(config =>
                {
                    config.SetApplicationName("satcom");
                    config.AddCommand<DumpCommand>("dump").WithDescription("The dump command.").WithExample(new[] { "dump", "osversion" }).WithExample(new[] { "dump", "osversion", "--loglevel verbose", "--forceSuccess true" }); ;
                }, args).UseSerilog(Log.Logger).UseConsoleLifetime(e => { e.SuppressStatusMessages = true; })
                ;

            var app = host.Build();

            await app.StartAsync();
            await app.WaitForShutdownAsync();

            

            // Capture the exit code from the shared ExitCodeHolder.
            int exitCode = CommandAppHostedService.CommandAppExitCode ?? -3;
            if (exitCode == 0)
            {
                Log.Logger.Information("Execution succeeded with exit code {ExitCode}", exitCode);
            }
            else
            {
                Log.Logger.Error("Command exited with error exit code {ExitCode}", exitCode);
            }

            await Log.CloseAndFlushAsync();

            app.Dispose();

            // Return the exit code.
            return exitCode;
        }
    }
}