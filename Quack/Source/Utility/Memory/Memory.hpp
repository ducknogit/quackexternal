#pragma once
#include <Windows.h>
#include <TlHelp32.h>
#include <filesystem>
#include <vector>

namespace Memory {
	DWORD Get_Process(const char* window_title);
	std::vector<DWORD> Get_Processes(const char* window_title);
	std::filesystem::path Get_Path(HANDLE handle);
	uintptr_t Get_Base_Address(DWORD pid, const wchar_t* module_name);

	template<typename T>
	T Read(HANDLE handle, uintptr_t address) {
		T buffer{};
		SIZE_T bytesRead = 0;
		if (ReadProcessMemory(handle, reinterpret_cast<LPCVOID>(address), &buffer, sizeof(T), &bytesRead) && bytesRead == sizeof(T)) {
			return buffer;
		}
		return T();
	}

	static bool Read_Physical(HANDLE handle, uintptr_t address, void* buffer, size_t size) {
		SIZE_T bytesRead = 0;
		return ReadProcessMemory(handle, reinterpret_cast<LPCVOID>(address), buffer, size, &bytesRead);
	}

	std::string Read_String(HANDLE handle, uintptr_t address);

	template<typename T>
	bool Write(HANDLE handle, uintptr_t address, const T& value) {
		SIZE_T bytesWritten = 0;
		return WriteProcessMemory(handle, reinterpret_cast<LPVOID>(address), &value, sizeof(T), &bytesWritten);
	}

	static bool Write_Physical(HANDLE handle, uintptr_t address, const void* buffer, size_t size) {
		SIZE_T bytesWritten = 0;
		return WriteProcessMemory(handle, reinterpret_cast<LPVOID>(address), buffer, size, &bytesWritten);
	}
}

namespace Resource {
	std::string Get_Resource(int idx);
	void Replace_String(std::string& source, const std::string_view toreplace, const std::string_view replacement);
}