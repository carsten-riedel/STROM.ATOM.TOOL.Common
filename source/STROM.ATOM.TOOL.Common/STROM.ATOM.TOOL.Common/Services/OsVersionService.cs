using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using Serilog.Core;
using Serilog.Events;

using Spectre.Console;

namespace STROM.ATOM.TOOL.Common.Services
{
    using System;
    using System.Threading;

    using Microsoft.Extensions.Logging;

    /// <summary>
    /// A service for retrieving and displaying the operating system version.
    /// </summary>
    public interface IOsVersionService
    {
        /// <summary>
        /// Displays the current operating system version.
        /// </summary>
        Task ShowOsVersion(CancellationToken cancellationToken);
    }

    /// <summary>
    /// A concrete implementation of IOsVersionService that writes the OS version to the console.
    /// </summary>
    public class OsVersionService : IOsVersionService
    {
        private readonly ILogger<OsVersionService> _logger;

        public OsVersionService(ILogger<OsVersionService> logger)
        {
            _logger = logger;
        }

        /// <inheritdoc />
        public async Task ShowOsVersion(CancellationToken cancellationToken)
        {
            _logger.LogDebug("Displaying the operating system version...");
            await Task.Delay(5000, cancellationToken);
            Console.WriteLine($"{Environment.OSVersion}");
            _logger.LogDebug("Operating system version displayed.");
        }
    }
}