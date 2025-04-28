using System.Numerics;
using SpacetimeDB;

[Type]
public partial struct DbVector3 {
        public float x;
    public float y;
    public float z;

    public DbVector3(float x, float y, float z)
    {
        this.x = x;
        this.y = y;
        this.z = z;
    }
}

public static partial class Module
{
    [Table(Name = "user", Public = true)]
    public partial class User
    {
        [PrimaryKey]
        public Identity Identity;
        public string Name = string.Empty;
        public bool Online;
    }

    [Table(Name = "message", Public = true)]
    public partial class Message
    {
        [PrimaryKey]
        [AutoInc]
        public int Id;
        public Identity Sender;
        public Timestamp Sent;
        public string Text = string.Empty;
    }

    [Table(Name = "player_data", Public = true)]
    public partial class PlayerData
    {
        [PrimaryKey]
        public Identity Player;
        public DbVector3 Position;
        public DbVector3 Rotation;
        public string CarType = "MINIVAN";
        public bool IsActive;
    }

    [Reducer]
    public static void SetName(ReducerContext ctx, string name)
    {
        name = ValidateName(name);

        var user = ctx.Db.user.Identity.Find(ctx.Sender);
        if (user is not null)
        {
            user.Name = name.Replace("\n", "")[..Math.Min(name.Length, 8)];
            ctx.Db.user.Identity.Update(user);
        }
    }

    /// Takes a name and checks if it's acceptable as a user's name.
    private static string ValidateName(string name)
    {
        if (string.IsNullOrEmpty(name))
        {
            throw new Exception("Names must not be empty");
        }
        return name;
    }

    [Reducer]
    public static void SendMessage(ReducerContext ctx, string text)
    {
        text = ValidateMessage(text);
        Log.Info(text);
        ctx.Db.message.Insert(
            new Message
            {
                Sender = ctx.Sender,
                Text = text.Replace("\n", "")[..Math.Min(text.Length, 50)],
                Sent = ctx.Timestamp,
            }
        );
    }

    /// Takes a message's text and checks if it's acceptable to send.
    private static string ValidateMessage(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            throw new ArgumentException("Messages must not be empty");
        }
        return text;
    }

    [Reducer]
    public static void UpdatePlayerData(ReducerContext ctx, DbVector3 position, DbVector3 rotation, string carType, bool isActive) {
        Log.Info($"{ctx.Sender} updated their position: {position} and rotation: {rotation}");
        var player_data = ctx.Db.player_data.Player.Find(ctx.Sender);
        if (player_data is null) {
            ctx.Db.player_data.Insert(new PlayerData {
                Player = ctx.Sender,
                Position = position,
                Rotation = rotation,
                CarType = carType,
                IsActive = true
            });
        }
        else {
            player_data.Position = position;
            player_data.Rotation = rotation;
            player_data.CarType = carType;
            player_data.IsActive = isActive;
            ctx.Db.player_data.Player.Update(player_data);
        }
    }

    [Reducer(ReducerKind.ClientConnected)]
    public static void ClientConnected(ReducerContext ctx)
    {
        Log.Info($"Connect {ctx.Sender}");
        var user = ctx.Db.user.Identity.Find(ctx.Sender);

        if (user is not null)
        {
            // If this is a returning user, i.e., we already have a `User` with this `Identity`,
            // set `Online: true`, but leave `Name` and `Identity` unchanged.
            user.Online = true;
            ctx.Db.user.Identity.Update(user);
        }
        else
        {
            // If this is a new user, create a `User` object for the `Identity`,
            // which is online, but hasn't set a name.
            ctx.Db.user.Insert(
                new User
                {
                    Name = "unnamed",
                    Identity = ctx.Sender,
                    Online = true,
                }
            );
        }
    }

    [Reducer(ReducerKind.ClientDisconnected)]
    public static void ClientDisconnected(ReducerContext ctx)
    {
        var user = ctx.Db.user.Identity.Find(ctx.Sender);

        if (user is not null)
        {
            // This user should exist, so set `Online: false`.
            user.Online = false;
            ctx.Db.user.Identity.Update(user);
        }
        else
        {
            // User does not exist, log warning
            Log.Warn("Warning: No user found for disconnected client.");
        }
    }
}
