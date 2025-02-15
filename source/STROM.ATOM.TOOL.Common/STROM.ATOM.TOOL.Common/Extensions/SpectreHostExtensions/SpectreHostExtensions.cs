using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using Spectre.Console.Cli;

using STROM.ATOM.TOOL.Common.Spectre;

namespace STROM.ATOM.TOOL.Common.Extensions.SpectreHostExtensions
{
    /// <summary>
    /// Provides extension methods to register Spectre.CommandApp within the Generic Host.
    /// </summary>
    public static class SpectreHostExtensions
    {
        // A global ExitCodeHolder instance to be used by all commands.
        public static ExitCodeHolder exitCodeHolder = new ExitCodeHolder();

        /// <summary>
        /// Configures and registers the Spectre.CommandApp as well as the hosted service that runs it asynchronously.
        /// Also registers the shared ExitCodeHolder.
        /// </summary>
        public static IHostBuilder AddSpectreCommandApp(this IHostBuilder builder, Action<IConfigurator> configure, string[] args)
        {
            builder.ConfigureServices((context, services) =>
            {
                // Register the shared ExitCodeHolder.
                services.AddSingleton(exitCodeHolder);

                // Create a TypeRegistrar to integrate Spectre with the Microsoft DI container.
                var registrar = new Spectre.TypeRegistrar(services);
                // Create the CommandApp instance.
                var commandApp = new CommandApp(registrar);
                // Allow the caller to configure the command pipeline.
                commandApp.Configure(configure);

                // Register the CommandApp in DI.
                services.AddSingleton(commandApp);

                // Register the hosted service that runs the CommandApp asynchronously.
                services.AddHostedService(provider =>
                    new SpectreCommandAppHostedService(
                        provider.GetRequiredService<CommandApp>(),
                        provider.GetRequiredService<ILogger<SpectreCommandAppHostedService>>(),
                        provider.GetRequiredService<IHostApplicationLifetime>(),
                        args,
                        provider.GetRequiredService<ExitCodeHolder>()));
            });
            return builder;
        }
    }
}
