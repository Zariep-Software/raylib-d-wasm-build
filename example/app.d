import raylib;

enum MAX_SPIKES = 128;

enum ASSETS_PATH = "assets/";
enum SPRITE_PATH = ASSETS_PATH ~ "Sprites/";
enum MUSIC_PATH = ASSETS_PATH ~ "Music/";
enum SFX_PATH = ASSETS_PATH ~ "sfx/";

enum spritePath(string file) = SPRITE_PATH ~ file ~ "\0";
enum musicPath(string file) = MUSIC_PATH ~ file ~ "\0";
enum sfxPath(string file) = SFX_PATH ~ file ~ "\0";


enum RUN_FRAMES = 4;
enum JUMP_FRAMES = 1;
enum RUN_FPS = 4.0f;

enum BASE_WIDTH = 1024;
enum BASE_HEIGHT = 600;
enum BASE_GROUND_Y = 350.0f;
enum BASE_PLAYER_SIZE = 160.0f;
enum SPIKE_MULT = 3.0f;
enum BASE_SPIKE_SIZE = 30.0f * SPIKE_MULT;

// Hitbox inset, grounded (running sprite)
enum PLAYER_HB_LEFT = 50.0f;
enum PLAYER_HB_RIGHT = 50.0f;
enum PLAYER_HB_TOP = 1.0f;
enum PLAYER_HB_BOTTOM = 10.0f;

// Hitbox inset, airborne (jump sprite)
enum PLAYER_HB_LEFT_JUMP = 60.0f;
enum PLAYER_HB_RIGHT_JUMP = 60.0f;
enum PLAYER_HB_TOP_JUMP = 15.0f;
enum PLAYER_HB_BOTTOM_JUMP = 30.0f;

enum SPIKE_HB_X = 8.0f * SPIKE_MULT;
enum SPIKE_HB_Y = 18.0f * SPIKE_MULT;
enum SPIKE_HB_W = 14.0f * SPIKE_MULT;
enum SPIKE_HB_H = 14.0f * SPIKE_MULT;

enum RESTART_DELAY = 0.3f;


enum EXPLOSION_SIZE_MULT = 1.0f;

struct Spike
{
	Rectangle drawRect;
	Rectangle hitbox;
}

struct Assets
{
	Texture2D running;
	Texture2D jump;
	Texture2D spike;
	Texture2D explosion;
	Texture2D bgTex;
	Texture2D groundTex;
	Music background;
	Sound explosionSfx;
	Sound jumpSfx;
}

struct Game
{
	float screenW;
	float screenH;
	float scale;
	float groundY;
	float playerSize;
	// Player
	Vector2 playerPos;
	float velocityY;
	bool grounded;
	float animTimer;
	int animFrame;
	// Obstacles
	Spike[MAX_SPIKES] spikes;
	size_t spikeCount;
	float spawnTimer;
	float obstacleSpeed;
	bool dead;
	float deadTimer;
	Vector2 explosionPos; // center of the explosion
	// Scrolling
	float bgScroll;
	float groundScroll;
}

bool showHitboxes = false; // toggled with F3

Rectangle PlayerHitbox(ref Game game)
{
	float s = game.scale;
	float l = game.grounded ? PLAYER_HB_LEFT : PLAYER_HB_LEFT_JUMP;
	float r = game.grounded ? PLAYER_HB_RIGHT : PLAYER_HB_RIGHT_JUMP;
	float t = game.grounded ? PLAYER_HB_TOP : PLAYER_HB_TOP_JUMP;
	float b = game.grounded ? PLAYER_HB_BOTTOM : PLAYER_HB_BOTTOM_JUMP;
	float x = game.playerPos.x + l * s;
	float y = game.playerPos.y + t * s;
	float w = game.playerSize - (l + r) * s;
	float h = game.playerSize - (t + b) * s;
	return Rectangle(x, y, w, h);
}

Game game;
Assets assets;

void LoadAssets(ref Assets a)
{
	a.running = LoadTexture(spritePath!"running.png".ptr);
	a.jump = LoadTexture(spritePath!"jump.png".ptr);
	a.spike = LoadTexture(spritePath!"spike.png".ptr);
	a.explosion = LoadTexture(spritePath!"explosion.png".ptr);

	a.bgTex = LoadTexture(spritePath!"background.png".ptr);
	a.groundTex = LoadTexture(spritePath!"ground.png".ptr);
	if (a.bgTex.id != 0)
		SetTextureWrap(a.bgTex, TextureWrap.TEXTURE_WRAP_REPEAT);
	if (a.groundTex.id != 0)
		SetTextureWrap(a.groundTex, TextureWrap.TEXTURE_WRAP_REPEAT);

	a.background = LoadMusicStream(musicPath!"background.ogg".ptr);
	a.background.looping = true;
	SetMusicVolume(a.background, 0.5f);

	a.explosionSfx = LoadSound(sfxPath!"explosion.ogg".ptr);
	a.jumpSfx = LoadSound(sfxPath!"jjump.ogg".ptr);
}

void UnloadAssets(ref Assets a)
{
	UnloadTexture(a.running);
	UnloadTexture(a.jump);
	UnloadTexture(a.spike);
	UnloadTexture(a.explosion);
	UnloadTexture(a.bgTex);
	UnloadTexture(a.groundTex);
	UnloadMusicStream(a.background);
	UnloadSound(a.explosionSfx);
	UnloadSound(a.jumpSfx);
}

void InitGame(ref Game game)
{
	game.screenW = cast(float) GetScreenWidth();
	game.screenH = cast(float) GetScreenHeight();
	game.scale = game.screenH / BASE_HEIGHT;
	game.groundY = BASE_GROUND_Y * game.scale;
	game.playerSize = BASE_PLAYER_SIZE * game.scale;

	game.playerPos = Vector2(150 * game.scale, game.groundY - game.playerSize);
	game.velocityY = 0;
	game.grounded = true;
	game.animTimer = 0;
	game.animFrame = 0;
	game.spawnTimer = 0;
	game.obstacleSpeed = 600 * game.scale;
	game.spikeCount = 0;
	game.dead = false;
	game.deadTimer = 0;
	game.explosionPos = Vector2(0, 0);
	game.bgScroll = 0;
	game.groundScroll = 0;
}

void RestartRun(ref Game game)
{
	InitGame(game);
	StopMusicStream(assets.background);
	PlayMusicStream(assets.background);
}

bool JumpPressed()
{
	bool pressed = false;
	int key;
	while ((key = GetKeyPressed()) != 0)
	{
		if (key != KeyboardKey.KEY_F3)
			pressed = true;
	}
	return pressed
		|| IsMouseButtonPressed(MouseButton.MOUSE_BUTTON_LEFT)
		|| IsGestureDetected(Gesture.GESTURE_TAP);
}

void UpdatePlayer(ref Game game, float dt)
{
	if (JumpPressed() && game.grounded)
	{
		game.velocityY = -500 * game.scale;
		game.grounded = false;
		PlaySound(assets.jumpSfx);
	}
	game.velocityY += 1200 * game.scale * dt;
	game.playerPos.y += game.velocityY * dt;
	if (game.playerPos.y >= game.groundY - game.playerSize)
	{
		game.playerPos.y = game.groundY - game.playerSize;
		game.velocityY = 0;
		game.grounded = true;
	}

	// Run animation
	if (game.grounded)
	{
		game.animTimer += dt;
		float frameTime = 1.0f / RUN_FPS;
		while (game.animTimer >= frameTime)
		{
			game.animTimer -= frameTime;
			game.animFrame = (game.animFrame + 1) % RUN_FRAMES;
		}
	}
	else
	{
		game.animTimer = 0;
		game.animFrame = 0;
	}
}

void AddSpike(ref Game game, float x)
{
	if (game.spikeCount >= MAX_SPIKES)
		return;
	float sz = BASE_SPIKE_SIZE * game.scale;
	auto ref s = game.spikes[game.spikeCount++];
	s.drawRect = Rectangle(x, game.groundY - sz, sz, sz);
	s.hitbox = Rectangle(x + SPIKE_HB_X * game.scale, game.groundY - SPIKE_HB_Y * game.scale,
						SPIKE_HB_W * game.scale, SPIKE_HB_H * game.scale);
}

void SpawnSpikes(ref Game game, float dt)
{
	game.spawnTimer += dt;
	if (game.spawnTimer < 2)
		return;
	game.spawnTimer = 0;
	int count = GetRandomValue(1, 3);
	foreach (i; 0 .. count)
	{
		AddSpike(game, game.screenW + (1 + i * 35 * SPIKE_MULT) * game.scale);
	}
}

void UpdateSpikes(ref Game game, float dt)
{
	foreach (i; 0 .. game.spikeCount)
	{
		auto ref s = game.spikes[i];
		s.drawRect.x -= game.obstacleSpeed * dt;
		s.hitbox.x -= game.obstacleSpeed * dt;
	}
	size_t i = 0;
	while (i < game.spikeCount)
	{
		if (game.spikes[i].drawRect.x < -50 * SPIKE_MULT * game.scale)
		{
			game.spikes[i] = game.spikes[game.spikeCount - 1];
			game.spikeCount--;
		}
		else
		{
			i++;
		}
	}
}

void CheckCollisions(ref Game game)
{
	Rectangle playerBox = PlayerHitbox(game);
	foreach (i; 0 .. game.spikeCount)
	{
		if (CheckCollisionRecs(playerBox, game.spikes[i].hitbox))
		{
			// Explosion appears where the spike was
			Rectangle d = game.spikes[i].drawRect;
			game.explosionPos = Vector2(d.x + d.width / 2, d.y + d.height / 2);

			game.spikes[i] = game.spikes[game.spikeCount - 1];
			game.spikeCount--;

			game.dead = true;
			game.deadTimer = 0;
			StopMusicStream(assets.background);
			PlaySound(assets.explosionSfx);
			return;
		}
	}
}

void UpdateGame(ref Game game, float dt)
{
	if (game.dead)
	{
		game.deadTimer += dt;
		if (game.deadTimer >= RESTART_DELAY && JumpPressed())
			RestartRun(game);
		return;
	}
	game.groundScroll += game.obstacleSpeed * dt;
	game.bgScroll += game.obstacleSpeed * 0.25f * dt; // parallax
	UpdatePlayer(game, dt);
	SpawnSpikes(game, dt);
	UpdateSpikes(game, dt);
	CheckCollisions(game);
}

void DrawPlayer(ref Game game)
{
	Color white = Colors.WHITE;
	Rectangle dest = Rectangle(game.playerPos.x, game.playerPos.y, game.playerSize, game.playerSize);

	Texture2D tex = game.grounded ? assets.running : assets.jump;
	int frames = game.grounded ? RUN_FRAMES : JUMP_FRAMES;
	int frame = game.grounded ? game.animFrame : 0;

	// Fallback
	if (tex.id == 0)
	{
		DrawRectangleRec(dest, white);
		return;
	}

	float fw = cast(float) tex.width / frames;
	Rectangle src = Rectangle(fw * frame, 0, fw, cast(float) tex.height);

	DrawTexturePro(tex, src, dest, Vector2(0, 0), 0, white);
}

void DrawSpike(ref Spike s)
{
	Color white = Colors.WHITE;
	if (assets.spike.id != 0)
	{
		Rectangle src = Rectangle(0, 0, cast(float) assets.spike.width, cast(float) assets.spike.height);
		DrawTexturePro(assets.spike, src, s.drawRect, Vector2(0, 0), 0, white);
	}
	else
	{
		DrawTriangle(
			Vector2(s.drawRect.x, s.drawRect.y + s.drawRect.height),
			Vector2(s.drawRect.x + s.drawRect.width, s.drawRect.y + s.drawRect.height),
			Vector2(s.drawRect.x + s.drawRect.width / 2, s.drawRect.y),
			white);
	}
}

void DrawExplosion(ref Game game)
{
	float size = BASE_SPIKE_SIZE * EXPLOSION_SIZE_MULT * game.scale;
	Rectangle dest = Rectangle(game.explosionPos.x - size / 2, game.explosionPos.y - size / 2, size, size);

	if (assets.explosion.id != 0)
	{
		Rectangle src = Rectangle(0, 0, cast(float) assets.explosion.width, cast(float) assets.explosion.height);
		DrawTexturePro(assets.explosion, src, dest, Vector2(0, 0), 0, Colors.WHITE);
	}
	else
	{
		DrawCircleV(game.explosionPos, size / 2, Colors.ORANGE);
	}
}

void DrawCenteredText(const(char)* text, float centerX, float y, int size, Color color)
{
	int w = MeasureText(text, size);
	DrawText(text, cast(int)(centerX - w / 2), cast(int) y, size, color);
}

void DrawTiled(Texture2D tex, Rectangle dest, float tileScale, float scroll)
{
	Rectangle src = Rectangle(scroll / tileScale, 0, dest.width / tileScale, dest.height / tileScale);
	DrawTexturePro(tex, src, dest, Vector2(0, 0), 0, Colors.WHITE);
}

void DrawGame(ref Game game)
{
	Color bg = Color(0x2A, 0x2A, 0x2A, 255);
	Color white = Colors.WHITE;
	float sw = cast(float) GetScreenWidth();
	float sh = cast(float) GetScreenHeight();

	ClearBackground(bg);

	// Background:
	if (assets.bgTex.id != 0)
		DrawTiled(assets.bgTex, Rectangle(0, 0, sw, sh), sh / assets.bgTex.height, game.bgScroll);

	// Ground
	Rectangle groundRect = Rectangle(0, game.groundY, sw, sh - game.groundY);
	if (assets.groundTex.id != 0)
		DrawTiled(assets.groundTex, groundRect, game.scale, game.groundScroll);
	else
		DrawRectangleRec(groundRect, Colors.GRAY);

	foreach (i; 0 .. game.spikeCount)
	{
		DrawSpike(game.spikes[i]);
		if (showHitboxes)
			DrawRectangleLinesEx(game.spikes[i].hitbox, 2, Colors.RED);
	}

	if (!game.dead)
	{
		DrawPlayer(game);
		if (showHitboxes)
			DrawRectangleLinesEx(PlayerHitbox(game), 2, Colors.GREEN);
	}
	else
	{
		DrawExplosion(game);

		float cx = game.screenW / 2;
		DrawCenteredText("GAME OVER", cx, game.screenH * 0.17f, cast(int)(40 * game.scale), Colors.RED);
		DrawCenteredText("Press any key to restart", cx, game.screenH * 0.17f + 55 * game.scale,
			cast(int)(20 * game.scale), white);
	}
}

bool update()
{
	import core.stdc.stdio : printf;
	static int frames;
	printf("frame %d, screen %dx%d\n", frames, GetScreenWidth(), GetScreenHeight());



	if (IsKeyPressed(KeyboardKey.KEY_ESCAPE))
		return true;

	if (IsKeyPressed(KeyboardKey.KEY_F3))
		showHitboxes = !showHitboxes;

	UpdateMusicStream(assets.background);

	float dt = GetFrameTime();
	UpdateGame(game, dt);

	BeginDrawing();
	scope (exit) EndDrawing();
	DrawGame(game);

	return false;
}

void ready()
{
	SetTraceLogLevel(TraceLogLevel.LOG_DEBUG);
	SetConfigFlags(ConfigFlags.FLAG_WINDOW_RESIZABLE);
	InitWindow(BASE_WIDTH, BASE_HEIGHT, "Infinite Jumper");
	InitAudioDevice();
	SetTargetFPS(60);

	LoadAssets(assets);
	InitGame(game);
	PlayMusicStream(assets.background);

	static void updateWindow(alias loopFunc)()
	{
		version (WebAssembly)
		{
			extern (C) static void webLoopFunc()
			{
				if (loopFunc()) emscripten_cancel_main_loop();
			}
			emscripten_set_main_loop(&webLoopFunc, 0, true);
		}
		else
		{
			while (true)
			{
				if (WindowShouldClose() || loopFunc()) break;
			}
		}
	}

	updateWindow!(update);

	UnloadAssets(assets);
	CloseAudioDevice();
	CloseWindow();
}

// Emscripten functions.
version (WebAssembly)
{
	extern (C) @system nothrow @nogc
	void emscripten_set_main_loop(void* ptr, int fps, int simulate_infinite_loop);
	extern (C) @system nothrow @nogc
	void emscripten_cancel_main_loop();
}

// -betterC trick.
version (D_BetterC)
{
	extern (C) void main() { ready(); }
}
else
{
	void main() { ready(); }
}