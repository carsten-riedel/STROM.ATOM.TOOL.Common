using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using Spectre.Console;

namespace STROM.ATOM.TOOL.Common.Services
{
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
    public class HelloWorldGreeter : IGreeter
    {
        public void Greet(string name)
        {
            AnsiConsole.WriteLine($"Hello {name}!");
        }
    }
}
