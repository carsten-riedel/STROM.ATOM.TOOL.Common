using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

using Spectre.Console.Cli;

namespace STROM.ATOM.TOOL.Common.Spectre
{
    public sealed class TypeResolver : ITypeResolver, IDisposable
    {
        private readonly IServiceProvider _provider;
        public TypeResolver(IServiceProvider provider) => _provider = provider ?? throw new ArgumentNullException(nameof(provider));
        public object? Resolve(Type? type) => type == null ? null : _provider.GetService(type);
        public void Dispose() { if (_provider is IDisposable disposable) disposable.Dispose(); }
    }

}
