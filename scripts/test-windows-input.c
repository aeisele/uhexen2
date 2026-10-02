/* Exercise the real Windows input code with controlled WM_INPUT payloads.
 * Build with test-windows-input.ps1; no game data or visible window required. */
#include <assert.h>
#include "quakedef.h"
#include "winquake.h"

/* Capture/position calls are simulated so these tests never seize the real
 * desktop cursor. Raw device registration below still uses the Windows API. */
static HWND test_foreground, test_capture;
static int cursor_warps, cursor_clips, cursor_hides;
static qboolean cursor_confined;
static HWND Test_Foreground(void) { return test_foreground; }
static BOOL Test_SetCursorPos(int x, int y) { cursor_warps++; return TRUE; }
static BOOL Test_ClipCursor(const RECT *rect)
{
	if (rect) cursor_clips++;
	cursor_confined = rect != NULL;
	return TRUE;
}
static HWND Test_SetCapture(HWND window) { test_capture = window; return NULL; }
static BOOL Test_ReleaseCapture(void) { test_capture = NULL; return TRUE; }
static int Test_ShowCursor(BOOL show) { if (!show) cursor_hides++; return 0; }
#define GetForegroundWindow Test_Foreground
#define SetCursorPos Test_SetCursorPos
#define ClipCursor Test_ClipCursor
#define SetCapture Test_SetCapture
#define ReleaseCapture Test_ReleaseCapture
#define ShowCursor Test_ShowCursor
#include "../engine/h2shared/in_win.c"

qboolean ActiveApp, Minimized;
HWND mainwindow;
int window_center_x, window_center_y;
RECT window_rect;
cvar_t _enable_mouse;
client_state_t cl;
kbutton_t in_strafe, in_mlook;
cvar_t sensitivity, lookstrafe, m_side, m_yaw, m_pitch, m_forward;
static int key_events;
static keydest_t input_dest = key_game;
keydest_t Key_GetDest(void) { return input_dest; }
void Key_Event(int key, qboolean down) { key_events++; }
void V_StopPitchDrift(void) {}

static RAWINPUT packet;
static UINT packet_size;
static UINT WINAPI ReadPacket(HRAWINPUT handle, UINT command, LPVOID data,
	PUINT size, UINT header_size)
{
	assert(command == RID_INPUT && header_size == sizeof(RAWINPUTHEADER));
	assert(*size >= sizeof(packet));
	memcpy(data, &packet, sizeof(packet));
	return packet_size;
}

static void Move(LONG x, LONG y, USHORT flags)
{
	packet.data.mouse.lLastX = x;
	packet.data.mouse.lLastY = y;
	packet.data.mouse.usFlags = flags;
	IN_RawInput(0);
}

static void TestCapture(qboolean raw)
{
	rawinput_active = raw;
	mouseinitialized = true;
	mouseactive = false;
	_enable_mouse.integer = 1;
	cursor_warps = cursor_clips = cursor_hides = 0;
	mouseshowtoggle = 1;

	/* Reject a request if any focus condition is false. */
	ActiveApp = false;
	test_foreground = mainwindow;
	IN_ActivateMouse();
	ActiveApp = true;
	Minimized = true;
	IN_ActivateMouse();
	Minimized = false;
	test_foreground = NULL; /* stale ActiveApp during a focus transition */
	IN_ActivateMouse();
	IN_HideMouse();
	assert(!mouseactive && !test_capture && !cursor_confined);
	assert(cursor_warps == 0 && cursor_clips == 0 && cursor_hides == 0);

	test_foreground = mainwindow;
	IN_SetQuakeMouseState();
	assert(mouseactive && test_capture == mainwindow && cursor_confined);
	assert(cursor_warps == 1 && cursor_clips == 1 && cursor_hides == 1);
	IN_ActivateMouse();
	IN_ActivateMouse();
	assert(cursor_warps == 1 && cursor_clips == 1 && cursor_hides == 1);

	test_foreground = NULL;
	IN_Accumulate();
	IN_UpdateClipCursor();
	IN_HideMouse();
	assert(cursor_warps == 1 && cursor_clips == 1 && cursor_hides == 1);
	IN_ActivateMouse();
	assert(!mouseactive && !test_capture && !cursor_confined);
	IN_ActivateMouse();
	assert(cursor_warps == 1 && cursor_clips == 1 && cursor_hides == 1);

	test_foreground = mainwindow;
	IN_SetQuakeMouseState();
	assert(mouseactive && cursor_warps == 2 && cursor_clips == 2);
	IN_DeactivateMouse();
	assert(!mouseactive && !test_capture && !cursor_confined);
}

int main(void)
{
	RAWINPUTDEVICE registered;
	UINT count = 1;
	usercmd_t cmd;
	mainwindow = CreateWindowExA(0, "STATIC", "Input test", 0,
		0, 0, 1, 1, NULL, NULL, GetModuleHandle(NULL), NULL);
	assert(mainwindow);
	test_foreground = mainwindow;
	rawinput_active = IN_InitRawInput();
	assert(rawinput_active);
	assert(GetRegisteredRawInputDevices(&registered, &count, sizeof(registered)) == 1);
	assert(registered.hwndTarget == mainwindow && registered.dwFlags == 0);
	pGetRawInputData = ReadPacket;
	packet_size = sizeof(packet);
	packet.header.dwType = RIM_TYPEMOUSE;
	packet.header.hDevice = (HANDLE)1;
	ActiveApp = mouseactive = true;

	Move(4, -3, 0);
	Move(2, 1, 0);
	assert(mx_accum == 6 && my_accum == -2);
	/* Low sensitivity must preserve sub-count movement. */
	sensitivity.value = 0.25f;
	m_yaw.value = m_pitch.value = 1;
	in_mlook.state = 1;
	memset(&cmd, 0, sizeof(cmd));
	IN_MouseMove(&cmd);
	assert(cl.viewangles[YAW] == -1.5f && cl.viewangles[PITCH] == -0.5f);
	assert(mx_accum == 0 && my_accum == 0);
	IN_MouseMove(&cmd);
	assert(cl.viewangles[YAW] == -1.5f && cl.viewangles[PITCH] == -0.5f);

	ActiveApp = false;
	Move(100, 100, 0);
	ActiveApp = true;
	Minimized = true;
	Move(100, 100, 0);
	Minimized = false;
	mouseactive = false;
	Move(100, 100, 0);
	mouseactive = true;
	assert(mx_accum == 0 && my_accum == 0);
	input_dest = key_menu;
	Move(100, 100, 0);
	input_dest = key_console;
	Move(100, 100, 0);
	input_dest = key_game;
	assert(mx_accum == 0 && my_accum == 0);
	packet_size = (UINT)-1;
	Move(100, 100, 0);
	packet_size = sizeof(RAWINPUTHEADER);
	Move(100, 100, 0);
	packet_size = sizeof(packet);
	packet.header.dwType = RIM_TYPEKEYBOARD;
	Move(100, 100, 0);
	packet.header.dwType = RIM_TYPEMOUSE;
	assert(mx_accum == 0 && my_accum == 0);

	Move(10000, 10000, MOUSE_MOVE_ABSOLUTE);
	assert(mx_accum == 0 && my_accum == 0);
	Move(20000, 20000, MOUSE_MOVE_ABSOLUTE);
	assert(mx_accum > 0 && my_accum > 0);
	IN_ClearStates();
	Move(60000, 60000, MOUSE_MOVE_ABSOLUTE);
	assert(mx_accum == 0 && my_accum == 0);
	packet.header.hDevice = (HANDLE)2;
	Move(0, 0, MOUSE_MOVE_ABSOLUTE | MOUSE_VIRTUAL_DESKTOP);
	assert(mx_accum == 0 && my_accum == 0);

	/* Raw button flags must not duplicate the legacy button messages. */
	packet.data.mouse.usButtonFlags = RI_MOUSE_LEFT_BUTTON_DOWN;
	Move(0, 0, 0);
	assert(key_events == 0);
	IN_MouseEvent(1);
	IN_MouseEvent(1);
	IN_MouseEvent(0);
	assert(key_events == 2);
	IN_ClearStates();
	assert(old_mouse_x == 0 && old_mouse_y == 0 && !raw_absolute_valid);

	TestCapture(true);
	TestCapture(false);
	rawinput_active = true; /* registration from IN_InitRawInput is still live */
	IN_ShutdownRawInput();
	assert(!rawinput_active);
	count = 0;
	assert(GetRegisteredRawInputDevices(NULL, &count, sizeof(registered)) == 0);
	assert(count == 0);
	DestroyWindow(mainwindow);
	puts("PASS: raw motion/buttons, capture focus guards, repeated activation, release/recapture, legacy cursor guards, cleanup");
	return 0;
}
