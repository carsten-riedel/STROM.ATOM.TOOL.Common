using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace STROM.ATOM.TOOL.Common.Spectre
{
    /// <summary>
    /// An ambient context to flow a cancellation token.
    /// </summary>
    public static class CommandCancellationTokenContext
    {
        public static AsyncLocal<CancellationToken> Token { get; } = new AsyncLocal<CancellationToken>();
    }
}
