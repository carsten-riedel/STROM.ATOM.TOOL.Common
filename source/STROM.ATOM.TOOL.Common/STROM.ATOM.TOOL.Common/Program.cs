using System;
using System.Threading;
using System.Threading.Tasks;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using Spectre.Console;
using Spectre.Console.Cli;

namespace STROM.ATOM.TOOL.Common
{
    #region Shared ExitCodeHolder & Ambient Cancellation

    /// <summary>
    /// Holds the exit code produced by the CommandApp.
    /// A null value indicates that no exit code has been set.
    /// </summary>
    public class ExitCodeHolder
    {
        public int? ExitCode { get; set; }
    }

    /// <summary>
    /// An ambient context to flow a cancellation token.
    /// </summary>
    public static class CommandCancellationTokenContext
    {
        public static AsyncLocal<CancellationToken> Token { get; } = new AsyncLocal<CancellationToken>();
    }
    #endregion

    #region CommandAppExtensions

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
    #endregion

    #region SpectreHostExtensions & DI Registration

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
                var registrar = new TypeRegistrar(services);
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
    #endregion

    #region Spectre DI Helpers

    /// <summary>
    /// Implements Spectre.Console.Cli's ITypeRegistrar for dependency injection using IServiceCollection.
    /// </summary>
    public sealed class TypeRegistrar : ITypeRegistrar
    {
        private readonly IServiceCollection _builder;
        public TypeRegistrar(IServiceCollection builder) => _builder = builder;

        public ITypeResolver Build() => new TypeResolver(_builder.BuildServiceProvider());

        public void Register(Type service, Type implementation) =>
            _builder.AddSingleton(service, implementation);

        public void RegisterInstance(Type service, object implementation) =>
            _builder.AddSingleton(service, implementation);

        public void RegisterLazy(Type service, Func<object> func)
        {
            if (func is null) throw new ArgumentNullException(nameof(func));
            _builder.AddSingleton(service, provider => func());
        }
    }

    /// <summary>
    /// Implements Spectre.Console.Cli's ITypeResolver using IServiceProvider.
    /// </summary>
    public sealed class TypeResolver : ITypeResolver, IDisposable
    {
        private readonly IServiceProvider _provider;
        public TypeResolver(IServiceProvider provider) => _provider = provider ?? throw new ArgumentNullException(nameof(provider));
        public object Resolve(Type type) => type == null ? null : _provider.GetService(type);
        public void Dispose() { if (_provider is IDisposable disposable) disposable.Dispose(); }
    }
    #endregion

    #region Abortable Command Infrastructure

    /// <summary>
    /// An abstract base class for commands designed to be abortable via cancellation.
    /// Inherits from Spectre.Console.Cli's Command<TSettings> and overrides Execute to call the async version.
    /// This version obtains the shared ExitCodeHolder from SpectreHostExtensions.
    /// </summary>
    public abstract class AbortableCommand<TSettings> : Command<TSettings>
        where TSettings : CommandSettings, new()
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

    /// <summary>
    /// A concrete abortable command that demonstrates asynchronous, cancellation-aware work.
    /// After 5 seconds it returns success (0), and if aborted it returns 99.
    /// </summary>
    public class DefaultAbortableCommand : AbortableCommand<DefaultAbortableCommand.Settings>
    {
        private readonly IGreeter _greeter;
        private readonly ILogger<DefaultAbortableCommand> _logger;

        public class Settings : CommandSettings
        {
            public string Name { get; set; } = "World";
        }

        public DefaultAbortableCommand(IGreeter greeter, ILogger<DefaultAbortableCommand> logger)
        {
            _greeter = greeter ?? throw new ArgumentNullException(nameof(greeter));
            _logger = logger;
        }

        public override async Task<int> ExecuteAsync(CommandContext context, Settings settings, CancellationToken cancellationToken)
        {
            _greeter.Greet(settings.Name);
            _logger.LogInformation("DefaultAbortableCommand started.");

            try
            {
                // Run for 5 seconds unless canceled.
                int totalSeconds = 5;
                for (int i = 0; i < totalSeconds; i++)
                {
                    _logger.LogInformation("Working... {Second}s", i + 1);
                    await Task.Delay(1000, cancellationToken);
                }
                _logger.LogInformation("DefaultAbortableCommand completed normally after 5 seconds.");
                return 0;
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("DefaultAbortableCommand canceled internally.");
                return 99;
            }
        }
    }

    public class DefaultAbortableCommand2 : AbortableCommand<DefaultAbortableCommand2.Settings>
    {
        private readonly IGreeter _greeter;
        private readonly ILogger<DefaultAbortableCommand> _logger;

        public class Settings : CommandSettings
        {
            public string Name { get; set; } = "World";
        }

        public DefaultAbortableCommand2(IGreeter greeter, ILogger<DefaultAbortableCommand> logger)
        {
            _greeter = greeter ?? throw new ArgumentNullException(nameof(greeter));
            _logger = logger;
        }

        public override async Task<int> ExecuteAsync(CommandContext context, Settings settings, CancellationToken cancellationToken)
        {
            _greeter.Greet(settings.Name);
            _logger.LogInformation("DefaultAbortableCommand started.");

            try
            {
                // Run for 5 seconds unless canceled.
                int totalSeconds = 5;
                for (int i = 0; i < totalSeconds; i++)
                {
                    _logger.LogInformation("Working... {Second}s", i + 1);
                    await Task.Delay(1000, cancellationToken);
                }
                _logger.LogInformation("DefaultAbortableCommand completed normally after 5 seconds.");
                return 0;
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("DefaultAbortableCommand canceled internally.");
                return 99;
            }
        }
    }

    /// <summary>
    /// A simple service for greeting.
    /// </summary>
    public interface IGreeter
    {
        void Greet(string name);
    }

    /// <summary>
    /// A concrete implementation of IGreeter that writes greetings to the console.
    /// </summary>
    public sealed class HelloWorldGreeter : IGreeter
    {
        public void Greet(string name)
        {
            AnsiConsole.WriteLine($"Hello {name}!");
        }
    }
    #endregion

    #region Hosted Service for CommandApp

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
                _logger.LogInformation("Starting CommandApp...");
                // RunAsync uses the ambient cancellation token set via AsyncLocal.
                await _commandApp.RunAsync(_args, stoppingToken);
                _logger.LogInformation("CommandApp finished.");

                if (!_exitCodeHolder.ExitCode.HasValue)
                    _exitCodeHolder.ExitCode = 0;

                _hostApplicationLifetime.StopApplication();
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation("CommandApp execution was canceled.");
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
    #endregion

    #region Program Entry Point

    /// <summary>
    /// The main entry point for the application.
    /// Configures the Generic Host, DI, and Spectre.CommandApp.
    /// </summary>
    public class Program
    {
        public static async Task<int> Main(string[] args)
        {
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
                    config.AddCommand<DefaultAbortableCommand>("default")
                          .WithDescription("The default abortable command.");
                    config.AddCommand<DefaultAbortableCommand2>("default2")
                            .WithDescription("The default abortable command2.");
                }, args)
                .Build();

            await host.RunAsync();

            // Return the exit code that was set.
            return SpectreHostExtensions.exitCodeHolder.ExitCode ?? -999;
        }


    }
    #endregion

}
