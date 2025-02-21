namespace STROM.ATOM.TOOL.Common.Tests
{
    using System.Threading;
    using System.Threading.Tasks;

    using global::STROM.ATOM.TOOL.Common.Extensions.StringExtensions;
    using global::STROM.ATOM.TOOL.Common.Services;

    using Microsoft.Extensions.DependencyInjection;
    using Microsoft.Extensions.Hosting;
    using Microsoft.VisualStudio.TestTools.UnitTesting;

    namespace STROM.ATOM.TOOL.Common.Tests
    {
        [TestClass]
        public sealed class OsVersionServiceTests
        {
            private static IHost? host;

            [AssemblyInitialize]
            public static void AssemblyInit(TestContext context)
            {
                // This method is called once for the test assembly, before any tests are run.
            }

            [AssemblyCleanup]
            public static void AssemblyCleanup()
            {
                // This method is called once for the test assembly, after all tests are run.
            }

            [ClassInitialize]
            public static void ClassInit(TestContext context)
            {
                // This method is called once for the test class, before any tests of the class are run.
                host = Host.CreateDefaultBuilder()
                    .ConfigureServices((ctx, services) =>
                    {
                        services.AddLogging();
                        services.AddTransient<IOsVersionService, OsVersionService>();
                    })
                    .Build();
            }

            [ClassCleanup]
            public static void ClassCleanup()
            {
                // This method is called once for the test class, after all tests of the class are run.
                host?.Dispose();
            }

            [TestInitialize]
            public void TestInit()
            {
                // This method is called before each test method.
            }

            [TestCleanup]
            public void TestCleanup()
            {
                // This method is called after each test method.
            }

            [TestMethod]
            public async Task TestOsVersionServiceIntegration()
            {
                // Resolve the service from the host's service provider.
                if (host is null) throw new InvalidOperationException("Host is not initialized.");
                IOsVersionService osVersionService = host.Services.GetRequiredService<IOsVersionService>();

                // Call the service method with a short delay and a cancellation token.
                await osVersionService.ShowOsVersion(100, CancellationToken.None);
            }

            [TestMethod]
            public void Versioning()
            {
                var mapped2 = Utility.Utility.MapDateTimeToUShorts();

                var start = new DateTime(2025, 2, 16);
                var end = start.AddDays(1);
                for (var i = start; i < end; i = i.AddHours(1))
                {
                    var mapped = Utility.Utility.MapDateTimeToUShorts(i);
                    Console.WriteLine($"{mapped.HighPart}-{mapped.LowPart}   {i.ToString()}");
                }
            }
        }
    }
}