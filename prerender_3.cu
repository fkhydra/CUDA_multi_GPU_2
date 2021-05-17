#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <math.h>
#include <stdio.h>
#include <windows.h>
#include <mmsystem.h>
#pragma comment(lib, "winmm.lib")
#include <d2d1.h>
#include <d2d1helper.h>
#pragma comment(lib, "d2d1")

//*****double buffering*****
#define SCREEN_WIDTH 1900
#define SCREEN_HEIGHT 1000
#define BLOCKSIZE 384

#define FRAMECOUNT 36
#define YROTANGLE 10

D2D1_RECT_U display_area;
ID2D1Bitmap* memkeptarolo = NULL;
unsigned int kepadat[SCREEN_WIDTH * SCREEN_HEIGHT];
ID2D1Factory* pD2DFactory = NULL;
ID2D1HwndRenderTarget* pRT = NULL;
typedef struct Vec3f {
	float x, y, z;
};
//**************************************

//**************PEGAZUS 3D************
#define MAX_OBJ_NUM 15000000
float zoo_value = 1.0;
int drawing_in_progress = 0;
int viewpoint = -500;
float persp_degree, current_zoom;
float rot_degree_x;
float rot_degree_y;
float rot_degree_z;
float rot_degree_x2 = 0;
float rot_degree_y2 = 90.0f;
float rot_degree_z2 = 0;
float Math_PI = 3.14159265358979323846;
float raw_verticesX[MAX_OBJ_NUM], raw_verticesY[MAX_OBJ_NUM], raw_verticesZ[MAX_OBJ_NUM];
int raw_vertex_counter;
int raw_vertices_length;
struct VEKTOR {
	float x;
	float y;
	float z;
};
VEKTOR Vector1, Vector2, vNormal;
VEKTOR vLight;
//*******CUDA*************
typedef struct DevLoadDistribution {
	int framecount;
	int rotation_list[360];
	int curr_frame;
};
DevLoadDistribution dev_distrlist[2];

unsigned int* dev0_image_data, * dev0_image_sequence[FRAMECOUNT];
float* dev0_zbuffer;
float* dev0_raw_verticesX, * dev0_raw_verticesY, * dev0_raw_verticesZ;
float* dev0_rotated_verticesX, * dev0_rotated_verticesY, * dev0_rotated_verticesZ;

unsigned int* dev1_image_data, * dev1_image_sequence[FRAMECOUNT];
float* dev1_zbuffer;
float* dev1_raw_verticesX, * dev1_raw_verticesY, * dev1_raw_verticesZ;
float* dev1_rotated_verticesX, * dev1_rotated_verticesY, * dev1_rotated_verticesZ;

//************************
void init_3D(void);
void data_transfer_to_GPU(void);
void cleanup_matrices(void);
void render_image_sequence(void);
__global__ void CUDA_rotation(int maxitemcount, float* rawarrayX, float* rawarrayY, float* rawarrayZ, float* rotarrayX, float* rotarrayY, float* rotarrayZ, float degree_cosx, float degree_sinx, float degree_cosy, float degree_siny, float degree_cosz, float degree_sinz);
void drawing_frame(int rotangle);
__global__ void render_objects(int maxitemcount, float* rotarrayX, float* rotarrayY, float* rotarrayZ, unsigned int* puffer, float* zpuffer, VEKTOR fenyvektor);
__global__ void zoom_in(int maxitemcount, float* rawarrayX, float* rawarrayY, float* rawarrayZ);
__global__ void zoom_out(int maxitemcount, float* rawarrayX, float* rawarrayY, float* rawarrayZ);
//************************************

//***********STANDARD WIN32API WINDOWING************
#define HIBA_00 TEXT("Error:Program initialisation process.")
HINSTANCE hInstGlob;
int SajatiCmdShow;
char szClassName[] = "WindowsApp";
HWND Form1; //Ablak kezeloje
LRESULT CALLBACK WndProc0(HWND, UINT, WPARAM, LPARAM);
//******************************************************

//*******for measurements********
long int vertex_counter, poly_counter;
float fps_stat;
int starttime;
int endtime;

//*****double buffering*****
void create_main_buffer(void);
void CUDA_cleanup_main_buffer(int devnum);
__global__ void CUDA_CleanUp_Zbuffer(float* zpuffer);
void swap_main_buffer(void);
//**************************************

//*****drawing algorithms*****
__device__ void CUDA_FillTriangle_Zbuffer(int x1, int y1, int z1, int x2, int y2, int z2, int x3, int y3, int z3, int color, unsigned int* puffer, float* zpuffer);
//**************************************

//********************************
//OBJ format handling
//********************************
float tomb_vertices[MAX_OBJ_NUM][3];
int tomb_faces[MAX_OBJ_NUM][5];
int tomb_vertices_length = 0, tomb_faces_length = 0;
int getelementcount(unsigned char csv_content[]);
void getelement(unsigned char csv_content[], unsigned int data_index, unsigned char csv_content2[]);
void obj_loader(void);

//*********************************
//The main entry point of our program
//*********************************
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, PSTR szCmdLine, int iCmdShow)
{
	static TCHAR szAppName[] = TEXT("StdWinClassName");
	HWND hwnd;
	MSG msg;
	WNDCLASS wndclass0;
	SajatiCmdShow = iCmdShow;
	hInstGlob = hInstance;

	//*********************************
	//Preparing Windows class
	//*********************************
	wndclass0.style = CS_HREDRAW | CS_VREDRAW;
	wndclass0.lpfnWndProc = WndProc0;
	wndclass0.cbClsExtra = 0;
	wndclass0.cbWndExtra = 0;
	wndclass0.hInstance = hInstance;
	wndclass0.hIcon = LoadIcon(NULL, IDI_APPLICATION);
	wndclass0.hCursor = LoadCursor(NULL, IDC_ARROW);
	wndclass0.hbrBackground = (HBRUSH)GetStockObject(LTGRAY_BRUSH);
	wndclass0.lpszMenuName = NULL;
	wndclass0.lpszClassName = TEXT("WIN0");

	//*********************************
	//Registering our windows class
	//*********************************
	if (!RegisterClass(&wndclass0))
	{
		MessageBox(NULL, HIBA_00, TEXT("Program Start"), MB_ICONERROR);
		return 0;
	}

	//*********************************
	//Creating the window
	//*********************************
	Form1 = CreateWindow(TEXT("WIN0"),
		TEXT("CUDA - GDI"),
		(WS_OVERLAPPED | WS_SYSMENU | WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX),
		0,
		0,
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		NULL,
		NULL,
		hInstance,
		NULL);

	//*********************************
	//Displaying the window
	//*********************************
	ShowWindow(Form1, SajatiCmdShow);
	UpdateWindow(Form1);

	//*********************************
	//Activating the message processing for our window
	//*********************************
	while (GetMessage(&msg, NULL, 0, 0))
	{
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}
	return msg.wParam;
}

//*********************************
//The window's callback funtcion: handling events
//*********************************
LRESULT CALLBACK WndProc0(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
	HDC hdc;
	PAINTSTRUCT ps;
	unsigned int xPos, yPos, xPos2, yPos2, fwButtons, i;

	switch (message)
	{
		//*********************************
		//When creating the window
		//*********************************
	case WM_CREATE:
		D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &pD2DFactory);
		pD2DFactory->CreateHwndRenderTarget(
			D2D1::RenderTargetProperties(),
			D2D1::HwndRenderTargetProperties(
				hwnd, D2D1::SizeU(SCREEN_WIDTH, SCREEN_HEIGHT)),
			&pRT);

		create_main_buffer();
		init_3D();
		obj_loader();

		cudaSetDevice(0);
		cudaMalloc((void**)&dev0_raw_verticesX, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev0_raw_verticesY, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev0_raw_verticesZ, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev0_rotated_verticesX, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev0_rotated_verticesY, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev0_rotated_verticesZ, MAX_OBJ_NUM * sizeof(float));
		for (i = 0; i < FRAMECOUNT; ++i) cudaMalloc((void**)&dev0_image_sequence[i], SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int));
		cudaMalloc((void**)&dev0_image_data, SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int));
		cudaMalloc((void**)&dev0_zbuffer, SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(float));

		cudaSetDevice(1);
		cudaMalloc((void**)&dev1_raw_verticesX, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev1_raw_verticesY, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev1_raw_verticesZ, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev1_rotated_verticesX, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev1_rotated_verticesY, MAX_OBJ_NUM * sizeof(float));
		cudaMalloc((void**)&dev1_rotated_verticesZ, MAX_OBJ_NUM * sizeof(float));
		for (i = 0; i < FRAMECOUNT; ++i) cudaMalloc((void**)&dev1_image_sequence[i], SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int));
		cudaMalloc((void**)&dev1_image_data, SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int));
		cudaMalloc((void**)&dev1_zbuffer, SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(float));

		data_transfer_to_GPU();
		render_image_sequence();
		if ((joyGetNumDevs()) > 0) joySetCapture(hwnd, JOYSTICKID1, NULL, FALSE);
		return 0;
		//*********************************
		//to eliminate color flickering
		//*********************************
	case WM_ERASEBKGND:
		return (LRESULT)1;
	case MM_JOY1MOVE:
		fwButtons = wParam;
		xPos = LOWORD(lParam);
		yPos = HIWORD(lParam);
		if (xPos == 65535) {
			rot_degree_y2 += YROTANGLE;
			if (rot_degree_y2 > 355) rot_degree_y2 = 0;
			//vLight.z += 20;
			drawing_frame(rot_degree_y2);
		}
		else if (xPos == 0) {
			rot_degree_y2 -= YROTANGLE;
			if (rot_degree_y2 < 0) rot_degree_y2 = 355;
			//vLight.z -= 20;
			drawing_frame(rot_degree_y2);
		}
		if (yPos == 65535) {
			rot_degree_x2 += 5.0;
			if (rot_degree_x2 > 355) rot_degree_x2 = 0;
			render_image_sequence();
			drawing_frame(rot_degree_y2);
		}
		else if (yPos == 0) {
			rot_degree_x2 -= 5.0;
			if (rot_degree_x2 < 0) rot_degree_x2 = 355;
			render_image_sequence();
			drawing_frame(rot_degree_y2);
		}
		if (fwButtons == 128) {
			rot_degree_z2 += 5.0;
			if (rot_degree_z2 > 355) rot_degree_z2 = 0;
			render_image_sequence();
			drawing_frame(rot_degree_y2);
		}
		else if (fwButtons == 64) {
			rot_degree_z2 -= 5.0;
			if (rot_degree_z2 < 0) rot_degree_z2 = 355;
			render_image_sequence();
			drawing_frame(rot_degree_y2);
		}

		if (fwButtons == 2)
		{
			int blockSize = BLOCKSIZE;
			int numBlocks = (raw_vertices_length + blockSize - 1) / blockSize;
			zoo_value *= 1.02;
			cudaSetDevice(0);
			zoom_in << <numBlocks, blockSize >> > (raw_vertices_length, dev0_raw_verticesX, dev0_raw_verticesY, dev0_raw_verticesZ);
			cudaSetDevice(1);
			zoom_in << <numBlocks, blockSize >> > (raw_vertices_length, dev1_raw_verticesX, dev1_raw_verticesY, dev1_raw_verticesZ);
			cudaDeviceSynchronize();
			render_image_sequence();
			drawing_frame(rot_degree_y2);
		}
		else if (fwButtons == 4)
		{
			int blockSize = BLOCKSIZE;
			int numBlocks = (raw_vertices_length + blockSize - 1) / blockSize;
			zoo_value /= 1.02;
			cudaSetDevice(0);
			zoom_out << <numBlocks, blockSize >> > (raw_vertices_length, dev0_raw_verticesX, dev0_raw_verticesY, dev0_raw_verticesZ);
			cudaSetDevice(1);
			zoom_out << <numBlocks, blockSize >> > (raw_vertices_length, dev1_raw_verticesX, dev1_raw_verticesY, dev1_raw_verticesZ);
			cudaDeviceSynchronize();
			render_image_sequence();
			drawing_frame(rot_degree_y2);
		}
		break;
		//*********************************
		//Repainting the client area of the window
		//*********************************
	case WM_PAINT:
		hdc = BeginPaint(hwnd, &ps);
		EndPaint(hwnd, &ps);
		return 0;
		//*********************************
		//Closing the window, freeing resources
		//*********************************
	case WM_CLOSE:
		pRT->Release();
		pD2DFactory->Release();

		cudaSetDevice(0);
		cudaFree(dev0_raw_verticesX);
		cudaFree(dev0_raw_verticesY);
		cudaFree(dev0_raw_verticesZ);
		cudaFree(dev0_rotated_verticesX);
		cudaFree(dev0_rotated_verticesY);
		cudaFree(dev0_rotated_verticesZ);
		for (i = 0; i < FRAMECOUNT; ++i) cudaFree(dev0_image_sequence[i]);
		cudaFree(dev0_image_data);
		cudaFree(dev0_zbuffer);

		cudaSetDevice(1);
		cudaFree(dev1_raw_verticesX);
		cudaFree(dev1_raw_verticesY);
		cudaFree(dev1_raw_verticesZ);
		cudaFree(dev1_rotated_verticesX);
		cudaFree(dev1_rotated_verticesY);
		cudaFree(dev1_rotated_verticesZ);
		for (i = 0; i < FRAMECOUNT; ++i) cudaFree(dev1_image_sequence[i]);
		cudaFree(dev1_image_data);
		cudaFree(dev1_zbuffer);

		DestroyWindow(hwnd);
		return 0;
		//*********************************
		//Destroying the window
		//*********************************
	case WM_DESTROY:
		PostQuitMessage(0);
		return 0;
	}
	return DefWindowProc(hwnd, message, wParam, lParam);
}

//********************************
//PEGAZUS 3D
//********************************
void create_main_buffer(void)
{
	pRT->CreateBitmap(D2D1::SizeU(SCREEN_WIDTH, SCREEN_HEIGHT),
		D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
			D2D1_ALPHA_MODE_IGNORE)), &memkeptarolo);
}

void CUDA_cleanup_main_buffer(int devnum)
{
	if (devnum == 0) cudaMemset(dev0_image_data, 255, SCREEN_HEIGHT * SCREEN_WIDTH * sizeof(unsigned int));
	else if (devnum == 1) cudaMemset(dev1_image_data, 255, SCREEN_HEIGHT * SCREEN_WIDTH * sizeof(unsigned int));
}

__global__ void CUDA_CleanUp_Zbuffer(float* zpuffer)
{
	int i;
	int index = (blockIdx.x * blockDim.x) + threadIdx.x;
	int stride = blockDim.x * gridDim.x;

	for (i = index; i < SCREEN_HEIGHT * SCREEN_WIDTH; i += stride)
	{
		zpuffer[i] = 999999;
	}
}

void swap_main_buffer(void)
{
	display_area.left = 0;
	display_area.top = 0;
	display_area.right = SCREEN_WIDTH;
	display_area.bottom = SCREEN_HEIGHT;
	memkeptarolo->CopyFromMemory(&display_area, kepadat, SCREEN_WIDTH * sizeof(unsigned int));
	pRT->BeginDraw();
	pRT->DrawBitmap(memkeptarolo, D2D1::RectF(0.0f, 0.0f, SCREEN_WIDTH, SCREEN_HEIGHT), 1.0f, D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR, NULL);
	pRT->EndDraw();
}

__device__ void CUDA_FillTriangle_Zbuffer(int x1, int y1, int z1, int x2, int y2, int z2, int x3, int y3, int z3, int color, unsigned int* puffer, float* zpuffer)
{
	int Ax, Ay, Bx, By, i, j, depth_value;
	int swapx, swapy, offset;
	Vec3f interpolate, helper_vector;
	if (y1 == y2 && y1 == y3) return;

	if (y1 > y2)
	{
		swapx = x1;
		swapy = y1;
		x1 = x2;
		y1 = y2;
		x2 = swapx;
		y2 = swapy;
	}
	if (y1 > y3)
	{
		swapx = x1;
		swapy = y1;
		x1 = x3;
		y1 = y3;
		x3 = swapx;
		y3 = swapy;
	}
	if (y2 > y3)
	{
		swapx = x3;
		swapy = y3;
		x3 = x2;
		y3 = y2;
		x2 = swapx;
		y2 = swapy;
	}
	int t_height = y3 - y1;
	for (i = 0; i < t_height; ++i)
	{
		bool second_half = i > y2 - y1 || y2 == y1;
		int segment_height = second_half ? y3 - y2 : y2 - y1;
		float alpha = (float)i / t_height;
		float beta = (float)(i - (second_half ? y2 - y1 : 0)) / segment_height;
		Ax = x1 + (x3 - x1) * alpha;
		Ay = y1 + (y3 - y1) * alpha;
		Bx = second_half ? x2 + (x3 - x2) * beta : x1 + (x2 - x1) * beta;
		By = second_half ? y2 + (y3 - y2) * beta : y1 + (y2 - y1) * beta;
		if (Ax > Bx)
		{
			swapx = Ax;
			swapy = Ay;
			Ax = Bx;
			Ay = By;
			Bx = swapx;
			By = swapy;
		}

		offset = (y1 + i) * SCREEN_WIDTH;
		for (j = Ax; j <= Bx; ++j)
		{
			helper_vector.x = (x2 - x1) * (y1 - (y1 + i)) - (x1 - j) * (y2 - y1);
			helper_vector.y = (x1 - j) * (y3 - y1) - (x3 - x1) * (y1 - (y1 + i));
			helper_vector.z = (x3 - x1) * (y2 - y1) - (x2 - x1) * (y3 - y1);
			if (abs((int)helper_vector.z) < 1) { interpolate.x = -1; interpolate.y = 0; interpolate.z = 0; }
			else
			{
				interpolate.x = 1.f - (helper_vector.x + helper_vector.y) / helper_vector.z;
				interpolate.y = helper_vector.y / helper_vector.z;
				interpolate.z = helper_vector.x / helper_vector.z;
			}
			if (interpolate.x < 0 || interpolate.y < 0 || interpolate.z < 0) continue;
			depth_value = (z1 * interpolate.x) + (z2 * interpolate.y) + (z3 * interpolate.z);
			if (zpuffer[offset + j] > depth_value)
			{
				zpuffer[offset + j] = depth_value;
				puffer[offset + j] = color;
			}
		}
	}
}

void init_3D(void)
{
	persp_degree = Math_PI / 180;
	rot_degree_x = 0 * Math_PI / 180; rot_degree_x2 = 0;
	rot_degree_y = 0 * Math_PI / 180; rot_degree_y2 = 0;
	rot_degree_z = 0 * Math_PI / 180; rot_degree_z2 = 0;
	//vLight.x = SCREEN_WIDTH / 3; vLight.y = -400000; vLight.z = 0;
	vLight.x = -0.5; vLight.y = -0.5; vLight.z = -0.9;
	cleanup_matrices();
}

void cleanup_matrices(void)
{
	raw_vertex_counter = 0;
	raw_vertices_length = 0;
}

void data_transfer_to_GPU(void)
{
	cudaSetDevice(0);
	cudaMemcpy(dev0_raw_verticesX, raw_verticesX, raw_vertices_length * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev0_raw_verticesY, raw_verticesY, raw_vertices_length * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev0_raw_verticesZ, raw_verticesZ, raw_vertices_length * sizeof(float), cudaMemcpyHostToDevice);
	cudaSetDevice(1);
	cudaMemcpy(dev1_raw_verticesX, raw_verticesX, raw_vertices_length * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev1_raw_verticesY, raw_verticesY, raw_vertices_length * sizeof(float), cudaMemcpyHostToDevice);
	cudaMemcpy(dev1_raw_verticesZ, raw_verticesZ, raw_vertices_length * sizeof(float), cudaMemcpyHostToDevice);
}

//********************************
//OBJ format handling
//********************************
int getelementcount(unsigned char csv_content[])
{
	int s1, s2;
	for (s1 = s2 = 0; s1 < strlen((const char*)csv_content); ++s1)
	{
		if (csv_content[s1] == 10) break;
		else if (csv_content[s1] == 32) ++s2;
	}
	return s2;
}

void getelement(unsigned char csv_content[], unsigned int data_index, unsigned char csv_content2[])
{
	int s1, s2, s3, s4 = 0;
	for (s1 = 0, s2 = 0; s1 < strlen((const char*)csv_content); ++s1)
	{
		if (csv_content[s1] == 32)
		{
			++s2;
			if (s2 == data_index)
			{
				for (s3 = s1 + 1; s3 < strlen((const char*)csv_content); ++s3)
				{
					if (csv_content[s3] == 32 || csv_content[s3] == 10)
					{
						csv_content2[s4] = 0;
						return;
					}
					else csv_content2[s4++] = csv_content[s3];
				}
			}
		}
	}
}

void obj_loader(void)
{
	FILE* objfile;
	int i, j;
	float data1, data2, data3;
	unsigned char row1[1024], row2[1024];
	int data_count, max_row_length = 250;
	char tempstr[200];

	objfile = fopen("mymodel.obj", "rt");
	if (objfile == NULL) return;

	vertex_counter = poly_counter = 0;
	tomb_vertices_length = tomb_vertices_length = 0;

	while (!feof(objfile))
	{
		fgets((char*)row1, max_row_length, objfile);

		if (row1[0] == 118 && row1[1] == 32) //*** 'v '
		{
			getelement(row1, 1, row2); data1 = atof((const char*)row2);
			getelement(row1, 2, row2); data2 = atof((const char*)row2);
			getelement(row1, 3, row2); data3 = atof((const char*)row2);
			tomb_vertices[tomb_vertices_length][0] = data1 * 4;
			tomb_vertices[tomb_vertices_length][1] = data2 * 4;
			tomb_vertices[tomb_vertices_length++][2] = data3 * 4;
		}
		else if (row1[0] == 102 && row1[1] == 32) //*** 'f '
		{
			data_count = getelementcount(row1);

			tomb_faces[tomb_faces_length][0] = data_count;
			for (i = 1; i < data_count + 1; ++i)
			{
				getelement(row1, i, row2);
				data1 = atof((const char*)row2);
				tomb_faces[tomb_faces_length][i] = data1 - 1;
			}
			++tomb_faces_length;
		}
	}
	fclose(objfile);
	int  base_index;
	for (i = 0; i < tomb_faces_length; ++i)
	{
		base_index = tomb_faces[i][1];
		if (tomb_faces[i][0] == 3)
		{
			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][1]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][1]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][1]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][2]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][2]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][2]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][3]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][3]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][3]][2];
			++poly_counter;
			vertex_counter += 3;
		}
		else if (tomb_faces[i][0] == 4)
		{
			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][1]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][1]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][1]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][2]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][2]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][2]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][3]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][3]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][3]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][1]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][1]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][1]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][3]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][3]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][3]][2];

			raw_verticesX[raw_vertices_length] = tomb_vertices[tomb_faces[i][4]][0];
			raw_verticesY[raw_vertices_length] = tomb_vertices[tomb_faces[i][4]][1];
			raw_verticesZ[raw_vertices_length++] = tomb_vertices[tomb_faces[i][4]][2];
			poly_counter += 2;
			vertex_counter += 6;
		}
	}
}

__global__ void CUDA_rotation(int maxitemcount, float* rawarrayX, float* rawarrayY, float* rawarrayZ, float* rotarrayX, float* rotarrayY, float* rotarrayZ, float degree_cosx, float degree_sinx, float degree_cosy, float degree_siny, float degree_cosz, float degree_sinz)
{
	int i;
	int index = blockIdx.x * blockDim.x + threadIdx.x;
	int stride = blockDim.x * gridDim.x;
	float t0;

	//rotation
	for (i = index; i < maxitemcount; i += stride)
	{
		rotarrayY[i] = (rawarrayY[i] * degree_cosx) - (rawarrayZ[i] * degree_sinx);
		rotarrayZ[i] = rawarrayY[i] * degree_sinx + rawarrayZ[i] * degree_cosx;

		rotarrayX[i] = rawarrayX[i] * degree_cosy + rotarrayZ[i] * degree_siny;
		rotarrayZ[i] = -rawarrayX[i] * degree_siny + rotarrayZ[i] * degree_cosy;// +

		t0 = rotarrayX[i];
		rotarrayX[i] = t0 * degree_cosz - rotarrayY[i] * degree_sinz + (SCREEN_WIDTH / 4);
		rotarrayY[i] = t0 * degree_sinz + rotarrayY[i] * degree_cosz + (SCREEN_HEIGHT / 6);
	}

	//perspective projection
	int s1;
	int viewpoint = -1100;
	float sx = SCREEN_WIDTH / 2;
	float sultra = SCREEN_HEIGHT / 2, sultra2 = SCREEN_HEIGHT / 3;
	int x_minusz_edge = 0, y_minusz_edge = 0, x_max_edge = SCREEN_WIDTH - 1, y_max_edge = SCREEN_HEIGHT - 1;
	float distance;

	for (i = index; i < maxitemcount; i += stride)
	{
		distance = 999999;

		if (rotarrayZ[i] < distance) distance = rotarrayZ[i];
		if (distance < viewpoint) { rotarrayZ[i] = -9999999; continue; }
		sultra = viewpoint / (viewpoint - rotarrayZ[i]);
		rotarrayX[i] = rotarrayX[i] * sultra + 400;
		rotarrayY[i] = (rotarrayY[i] * sultra) + sultra2;
		if (rotarrayX[i] < x_minusz_edge || rotarrayX[i] > x_max_edge) { rotarrayZ[i] = -9999999; continue; }
		if (rotarrayY[i] < y_minusz_edge || rotarrayY[i] > y_max_edge) { rotarrayZ[i] = -9999999; continue; }
	}
}

void render_image_sequence(void)
{
	int i;
	char hibauzenet[256];
	char tempstr[255], tempstr2[255];

	if (drawing_in_progress == 1) return;
	drawing_in_progress = 1;

	int blockSize = BLOCKSIZE;
	int numBlocks = (raw_vertices_length + blockSize - 1) / blockSize;

	float degree_siny;
	float degree_cosy;

	dev_distrlist[0].framecount = 26;
	dev_distrlist[1].framecount = 10;
	for (i = 0; i < 2; ++i) dev_distrlist[i].curr_frame = 0;

	for (i = 0; i < 26; ++i) dev_distrlist[0].rotation_list[i] = (i + 10) * YROTANGLE;
	for (i = 0; i < 10; ++i) dev_distrlist[1].rotation_list[i] = i * YROTANGLE;

	for (i = 0; i < FRAMECOUNT; ++i)
	{
		if (i == dev_distrlist[0].framecount) break;

		strcpy(tempstr2, "Pre-render: ");
		_itoa(i, tempstr, 10);
		strcat(tempstr2, tempstr);
		SetWindowTextA(Form1, tempstr2);

		rot_degree_x = rot_degree_x2 * Math_PI / 180;
		rot_degree_z = rot_degree_z2 * Math_PI / 180;
		float degree_sinx = sin(rot_degree_x);
		float degree_cosx = cos(rot_degree_x);
		float degree_sinz = sin(rot_degree_z);
		float degree_cosz = cos(rot_degree_z);

		//**************************************************
		if (dev_distrlist[0].curr_frame < dev_distrlist[0].framecount)
		{
			rot_degree_y = dev_distrlist[0].rotation_list[i] * Math_PI / 180;// rot_degree_y2
			degree_siny = sin(rot_degree_y);
			degree_cosy = cos(rot_degree_y);
			cudaSetDevice(0);
			CUDA_rotation << <numBlocks, blockSize >> > (raw_vertices_length, dev0_raw_verticesX, dev0_raw_verticesY, dev0_raw_verticesZ, dev0_rotated_verticesX, dev0_rotated_verticesY, dev0_rotated_verticesZ, degree_cosx, degree_sinx, degree_cosy, degree_siny, degree_cosz, degree_sinz);

		}
		if (dev_distrlist[1].curr_frame < dev_distrlist[1].framecount)
		{
			rot_degree_y = dev_distrlist[1].rotation_list[i] * Math_PI / 180;// rot_degree_y2
			degree_siny = sin(rot_degree_y);
			degree_cosy = cos(rot_degree_y);
			cudaSetDevice(1);
			CUDA_rotation << <numBlocks, blockSize >> > (raw_vertices_length, dev1_raw_verticesX, dev1_raw_verticesY, dev1_raw_verticesZ, dev1_rotated_verticesX, dev1_rotated_verticesY, dev1_rotated_verticesZ, degree_cosx, degree_sinx, degree_cosy, degree_siny, degree_cosz, degree_sinz);

		}
		cudaDeviceSynchronize();

		//**************************************************
		if (dev_distrlist[0].curr_frame < dev_distrlist[0].framecount)
		{
			cudaSetDevice(0);
			CUDA_cleanup_main_buffer(0);
			CUDA_CleanUp_Zbuffer << < ((SCREEN_WIDTH * SCREEN_HEIGHT) + BLOCKSIZE - 1) / BLOCKSIZE, BLOCKSIZE >> > (dev0_zbuffer);
		}
		if (dev_distrlist[1].curr_frame < dev_distrlist[1].framecount)
		{
			cudaSetDevice(1);
			CUDA_cleanup_main_buffer(1);
			CUDA_CleanUp_Zbuffer << < ((SCREEN_WIDTH * SCREEN_HEIGHT) + BLOCKSIZE - 1) / BLOCKSIZE, BLOCKSIZE >> > (dev1_zbuffer);
		}
		cudaDeviceSynchronize();

		//**************************************************
		if (dev_distrlist[0].curr_frame < dev_distrlist[0].framecount)
		{
			cudaSetDevice(0);
			render_objects << <128, BLOCKSIZE >> > (raw_vertices_length, dev0_rotated_verticesX, dev0_rotated_verticesY, dev0_rotated_verticesZ, dev0_image_data, dev0_zbuffer, vLight);
		}
		if (dev_distrlist[1].curr_frame < dev_distrlist[1].framecount)
		{
			cudaSetDevice(1);
			render_objects << <128, BLOCKSIZE >> > (raw_vertices_length, dev1_rotated_verticesX, dev1_rotated_verticesY, dev1_rotated_verticesZ, dev1_image_data, dev1_zbuffer, vLight);
		}
		cudaDeviceSynchronize();

		//**************************************************
		if (dev_distrlist[0].curr_frame < dev_distrlist[0].framecount)
		{
			cudaSetDevice(0);
			cudaMemcpy(dev0_image_sequence[dev_distrlist[0].rotation_list[i] / YROTANGLE], dev0_image_data, SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int), cudaMemcpyDeviceToDevice);
			++dev_distrlist[0].curr_frame;
		}
		if (dev_distrlist[1].curr_frame < dev_distrlist[1].framecount)
		{
			cudaSetDevice(1);
			cudaMemcpy(dev1_image_sequence[dev_distrlist[1].rotation_list[i] / YROTANGLE], dev1_image_data, SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int), cudaMemcpyDeviceToDevice);
			++dev_distrlist[1].curr_frame;
		}
	}

	strcpy_s(hibauzenet, cudaGetErrorString(cudaGetLastError()));
	SetWindowTextA(Form1, hibauzenet);

	drawing_in_progress = 0;
}

void drawing_frame(int rotangle)
{
	int i = rotangle / YROTANGLE;
	char tempstr[255], tempstr2[255];
	char hibauzenet[256];

	if (drawing_in_progress == 1) return;
	drawing_in_progress = 1;

	strcpy(tempstr2, "Vertices: ");
	_itoa(vertex_counter, tempstr, 10); strcat(tempstr2, tempstr); strcat(tempstr2, " Polygons: ");
	_itoa(poly_counter, tempstr, 10); strcat(tempstr2, tempstr); strcat(tempstr2, " Z ordered: ");

	starttime = GetTickCount();

	if (i >= 0 && i <= 9)
	{
		cudaSetDevice(1);
		cudaMemcpy(kepadat, dev1_image_sequence[i], SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int), cudaMemcpyDeviceToHost);
	}
	else if (i >= 10 && i <= 35)
	{
		cudaSetDevice(0);
		cudaMemcpy(kepadat, dev0_image_sequence[i], SCREEN_WIDTH * SCREEN_HEIGHT * sizeof(unsigned int), cudaMemcpyDeviceToHost);
	}

	swap_main_buffer();//**

	endtime = GetTickCount();
	if ((endtime - starttime) == 0) ++endtime;
	fps_stat = 1000 / (endtime - starttime); strcat(tempstr2, " FPS: "); _itoa(fps_stat, tempstr, 10); strcat(tempstr2, tempstr);
	strcat(tempstr2, ", X: "); _itoa(rot_degree_x2, tempstr, 10); strcat(tempstr2, tempstr);
	strcat(tempstr2, ", Y: "); _itoa(rot_degree_y2, tempstr, 10); strcat(tempstr2, tempstr);
	strcat(tempstr2, ", Z: "); _itoa(rot_degree_z2, tempstr, 10); strcat(tempstr2, tempstr);
	strcat(tempstr2, ", FRAME: "); _itoa(i, tempstr, 10); strcat(tempstr2, tempstr);
	strcpy_s(hibauzenet, cudaGetErrorString(cudaGetLastError()));
	strcat(tempstr2, ", CUDA: "); strcat(tempstr2, hibauzenet);
	SetWindowTextA(Form1, tempstr2);
	drawing_in_progress = 0;
}

__global__ void render_objects(int maxitemcount, float* rotarrayX, float* rotarrayY, float* rotarrayZ, unsigned int* puffer, float* zpuffer, VEKTOR fenyvektor)
{
	int i, px, py, tesztcolor;
	int index = (blockIdx.x * blockDim.x) + (threadIdx.x * 3);
	int stride = blockDim.x * gridDim.x;
	float Light_intensity, Vector_length;
	VEKTOR Vector1, Vector2, vNormal, vNormalized;//for visibility check

	for (i = index; i < maxitemcount - 2; i += stride)
	{
		if ((rotarrayZ[i] < -9000000) || (rotarrayZ[i + 1] < -9000000) || (rotarrayZ[i + 2] < -9000000)) continue;

		// for visibility check
		Vector1.x = rotarrayX[i + 1] - rotarrayX[i];
		Vector1.y = rotarrayY[i + 1] - rotarrayY[i];
		Vector1.z = rotarrayZ[i + 1] - rotarrayZ[i];
		Vector2.x = rotarrayX[i + 2] - rotarrayX[i];
		Vector2.y = rotarrayY[i + 2] - rotarrayY[i];
		Vector2.z = rotarrayZ[i + 2] - rotarrayZ[i];

		vNormal.x = ((Vector1.y * Vector2.z) - (Vector1.z * Vector2.y));
		vNormal.y = ((Vector1.z * Vector2.x) - (Vector1.x * Vector2.z));
		vNormal.z = ((Vector1.x * Vector2.y) - (Vector1.y * Vector2.x));
		if (vNormal.z > 0) continue;

		Vector_length = sqrtf((vNormal.x * vNormal.x) + (vNormal.y * vNormal.y) + (vNormal.z * vNormal.z));
		vNormalized.x = vNormal.x / Vector_length;
		vNormalized.y = vNormal.y / Vector_length;
		vNormalized.z = vNormal.z / Vector_length;
		Light_intensity = ((vNormalized.x * fenyvektor.x) + (vNormalized.y * fenyvektor.y) + (vNormalized.z * fenyvektor.z));
		if (Light_intensity > 1) Light_intensity = 1;
		else if (Light_intensity < 0) Light_intensity = 0;

		tesztcolor = RGB(255 * Light_intensity, 255 * Light_intensity, 255 * Light_intensity);

		CUDA_FillTriangle_Zbuffer(rotarrayX[i], rotarrayY[i], rotarrayZ[i], rotarrayX[i + 1], rotarrayY[i + 1], rotarrayZ[i + 1], rotarrayX[i + 2], rotarrayY[i + 2], rotarrayZ[i + 2], tesztcolor, puffer, zpuffer);

	}
}

__global__ void zoom_in(int maxitemcount, float* rawarrayX, float* rawarrayY, float* rawarrayZ)
{
	int i;
	int index = (blockIdx.x * blockDim.x) + (threadIdx.x * 1);
	int stride = blockDim.x * gridDim.x;
	for (i = index; i < maxitemcount; i += stride)
	{
		rawarrayX[i] *= 1.2;
		rawarrayY[i] *= 1.2;
		rawarrayZ[i] *= 1.2;
	}
}

__global__ void zoom_out(int maxitemcount, float* rawarrayX, float* rawarrayY, float* rawarrayZ)
{
	int i;
	int index = (blockIdx.x * blockDim.x) + (threadIdx.x * 1);
	int stride = blockDim.x * gridDim.x;
	for (i = index; i < maxitemcount; i += stride)
	{
		rawarrayX[i] /= 1.2;
		rawarrayY[i] /= 1.2;
		rawarrayZ[i] /= 1.2;
	}
}