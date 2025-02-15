using System;
using System.Threading.Tasks;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

using Serilog;

using STROM.ATOM.TOOL.Common.Commands;
using STROM.ATOM.TOOL.Common.Extensions.CommandAppExtensions;
using STROM.ATOM.TOOL.Common.Extensions.s;
using STROM.ATOM.TOOL.Common.Extensions.SpectreHostExtensions;
using STROM.ATOM.TOOL.Common.Serilog;
using STROM.ATOM.TOOL.Common.Services;
using STROM.ATOM.TOOL.Common.Spectre;

namespace STROM.ATOM.TOOL.Common
{
    public class Program
    {
        public static async Task<int> Main(string[] args)
        {
            var loggconfig = new LoggerConfiguration()
                .MinimumLevel.Verbose()
                .Enrich.FromLogContext()
                .WriteTo.Async(e => e.Console(theme: Theme.ClarionDusk))
                .CreateLogger();

            Log.Logger = loggconfig;

            // Build the host.
            var host = Host.CreateDefaultBuilder(args)
                .ConfigureServices((context, services) =>
                {
                    // Register shared services.
                    services.AddSingleton<IGreeter, HelloWorldGreeter>();
                })
                .AddSpectreCommandApp(config =>
                {
                    // Register your abortable command.
                    config.AddCommand<DefaultAbortableCommand>("default").WithDescription("The default abortable command.");
                    config.AddCommand<DefaultAbortableCommand2>("default2").WithDescription("The default abortable command2.");
                }, args).UseSerilog(Log.Logger).UseConsoleLifetime(e => { e.SuppressStatusMessages = true; })
                .Build();

            await host.RunAsync();

            // Capture the exit code from the shared ExitCodeHolder.
            int exitCode = SpectreHostExtensions.exitCodeHolder.ExitCode ?? -999;
            if (exitCode == 0)
            {
                MarkupResult result = await SpectreConsole.WriteTemplateAsync(
                    "{roleName}: {roleValue}, {nameName}: {nameValue}, {messageName}: {messageValue}",
                    new object[] {
                                "[lightsteelblue1 on grey]", "[lightsteelblue1 on black]",
                                    "[yellow on grey]", "[yellow on black]",
                                    "[lime on grey]", "[lime on black]",
                    },
                    "Role", "Assistant".PadLimit(10),
                    "Name", "Bob".PadLimit(10),
                    "Message", DateTime.Now.ToString("D").PadLimit(55)
                    );

                Spectre.SpectreConsole.WriteLine("Execution succeeded with exit code {ExitCode}", new object[] {"[underline red]" }, exitCode);   
                Log.Logger.Information(result.MessageTemplate, result.PropertyValues);
            }
            else
            {
                Log.Logger.Error("Command exited with error exit code {ExitCode}", exitCode);
            }

            await Log.CloseAndFlushAsync();

            // Return the exit code.
            return exitCode;
        }
    }
}