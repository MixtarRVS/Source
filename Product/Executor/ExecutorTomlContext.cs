using Tomlyn.Model;
using Tomlyn.Serialization;

namespace Mixtar.Product.Executor;

[TomlSerializable(typeof(TomlTable))]
internal partial class ExecutorTomlContext : TomlSerializerContext
{
}