#include "memory.hpp"
#include "Update/Offsets.hpp"
#include "Resource/Resource.h"

namespace Memory {
	DWORD Get_Process(const char* window_title) {
		HWND hwnd = FindWindowA(nullptr, window_title);
		if (!hwnd) return 0;

		DWORD pid = 0;
		GetWindowThreadProcessId(hwnd, &pid);
		return pid;
	}

	std::vector<DWORD> Get_Processes(const char* window_title) {
		std::vector<DWORD> pids;
		std::string target(window_title);

		struct EnumData {
			const std::string* title;
			std::vector<DWORD>* pids;
		} data{ &target, &pids };

		EnumWindows([](HWND hwnd, LPARAM lParam) -> BOOL {
			auto* d = reinterpret_cast<EnumData*>(lParam);
			char title[256];
			GetWindowTextA(hwnd, title, sizeof(title));

			if (d->title && strcmp(title, d->title->c_str()) == 0) {
				DWORD pid = 0;
				GetWindowThreadProcessId(hwnd, &pid);
				if (pid != 0)
					d->pids->push_back(pid);
			}
			return TRUE;
		}, reinterpret_cast<LPARAM>(&data));
		return pids;
	}

	std::filesystem::path Get_Path(HANDLE handle) {
		char buffer[MAX_PATH];
		DWORD buffer_size = sizeof(buffer);

		if (QueryFullProcessImageNameA(handle, 0, buffer, &buffer_size)) {
			return std::filesystem::path(buffer);
		}
		return {};
	}

	uintptr_t Get_Base_Address(DWORD pid, const wchar_t* module_name) {
		HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid);
		if (snapshot == INVALID_HANDLE_VALUE) return 0;

		MODULEENTRY32 moduleEntry{};
		moduleEntry.dwSize = sizeof(moduleEntry);

		uintptr_t baseAddress = 0;
		if (Module32First(snapshot, &moduleEntry)) {
			do {
				if (_wcsicmp(moduleEntry.szModule, module_name) == 0) {
					baseAddress = reinterpret_cast<uintptr_t>(moduleEntry.modBaseAddr);
					break;
				}
			} while (Module32Next(snapshot, &moduleEntry));
		}
		CloseHandle(snapshot);
		return baseAddress;
	}

	std::string Read_String(HANDLE handle, uintptr_t address) {
		auto length = Read<int>(handle, address + 0x18);
		if (length >= 16)
			address = Read<uintptr_t>(handle, address);

		std::string string;
		for (int i = 0; char ch = Read<char>(handle, address + i); i += sizeof(char)) {
			if (ch == '\0') break; // null terminator means string end
			string.push_back(ch);
		}
		return string;
	}
}

namespace Resource {
	std::string Get_Resource(int idx) {
		HMODULE HModule = NULL;
		GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, reinterpret_cast<LPCWSTR>(&Get_Resource), &HModule);
		if (!HModule) return "";

		HRSRC ResourceHandle = FindResourceW(HModule, MAKEINTRESOURCEW(idx), (LPCWSTR)RT_RCDATA);
		if (!ResourceHandle) return "";

		HGLOBAL LoadedResource = LoadResource(HModule, ResourceHandle);
		if (!LoadedResource) return "";

		DWORD ResourceSize = SizeofResource(HModule, ResourceHandle);
		void* Data = LockResource(LoadedResource);

		std::string code = std::string(static_cast<char*>(Data), ResourceSize);
		return code;
	}

	void Replace_String(std::string& source, const std::string_view toreplace, const std::string_view replacement) {
		size_t pos = source.find(toreplace);
		if (pos != std::string::npos) {
			source.replace(pos, toreplace.length(), replacement);
		}
	}
}