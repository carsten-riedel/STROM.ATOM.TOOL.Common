using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace STROM.ATOM.TOOL.Common.Spectre
{
    /// <summary>
    /// Holds the exit code produced by the CommandApp.
    /// A null value indicates that no exit code has been set.
    /// </summary>
    public class ExitCodeHolder
    {
        public int? ExitCode { get; set; }
    }
}
