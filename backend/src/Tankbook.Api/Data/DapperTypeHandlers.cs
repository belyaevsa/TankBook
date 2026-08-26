using System.Data;
using Dapper;

namespace Tankbook.Api.Data;

/// <summary>
/// Dapper does not natively map <see cref="DateOnly"/> as a parameter or member
/// type (Npgsql does, but Dapper's parameter engine rejects it before Npgsql ever
/// sees the value). This handler bridges the two: parameters are sent as
/// <see cref="DbType.Date"/> and read values (Npgsql 10 returns DateOnly for a
/// <c>date</c> column) are normalized back to DateOnly.
/// </summary>
public sealed class DateOnlyTypeHandler : SqlMapper.TypeHandler<DateOnly>
{
    public override void SetValue(IDbDataParameter parameter, DateOnly value)
    {
        parameter.DbType = DbType.Date;
        parameter.Value = value.ToDateTime(TimeOnly.MinValue);
    }

    public override DateOnly Parse(object value)
    {
        return value switch
        {
            DateOnly dateOnly => dateOnly,
            DateTime dateTime => DateOnly.FromDateTime(dateTime),
            string text => DateOnly.Parse(text, System.Globalization.CultureInfo.InvariantCulture),
            _ => throw new InvalidCastException($"Cannot convert a {value.GetType().Name} to DateOnly."),
        };
    }
}

/// <summary>Registers the Dapper DateOnly handler once, idempotently (both Program and the L2 tests call it).</summary>
public static class DapperTypeHandlers
{
    private static readonly object Gate = new();
    private static bool _registered;

    public static void Register()
    {
        if (_registered)
        {
            return;
        }

        lock (Gate)
        {
            if (_registered)
            {
                return;
            }

            SqlMapper.AddTypeHandler(new DateOnlyTypeHandler());
            _registered = true;
        }
    }
}
