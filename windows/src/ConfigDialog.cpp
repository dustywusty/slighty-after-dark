#include "ConfigDialog.h"

#include "Savers.h"
#include "Settings.h"
#include "resource.h"

#include <commctrl.h>

#include <string>

namespace {

void ConfigureSlider(HWND dialog, int sliderID, int minimum, int maximum, int value)
{
    HWND slider = GetDlgItem(dialog, sliderID);
    SendMessageW(slider, TBM_SETRANGE, FALSE, MAKELPARAM(minimum, maximum));
    SendMessageW(slider, TBM_SETTICFREQ, 25, 0);
    SendMessageW(slider, TBM_SETLINESIZE, 0, 5);
    SendMessageW(slider, TBM_SETPAGESIZE, 0, 25);
    SendMessageW(slider, TBM_SETPOS, TRUE, value);
}

int SliderValue(HWND dialog, int sliderID)
{
    return static_cast<int>(SendDlgItemMessageW(dialog, sliderID, TBM_GETPOS, 0, 0));
}

void UpdatePercentLabel(HWND dialog, int sliderID, int labelID)
{
    std::wstring text = std::to_wstring(SliderValue(dialog, sliderID)) + L"%";
    SetDlgItemTextW(dialog, labelID, text.c_str());
}

void InitializeDialog(HWND dialog)
{
    Settings settings = Settings::Load();

    HWND saverList = GetDlgItem(dialog, IDC_SAVER);
    for (size_t index = 0; index < kSavers.size(); ++index) {
        std::wstring title(kSavers[index].title);
        SendMessageW(saverList, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(title.c_str()));
        if (kSavers[index].filename == settings.saver) {
            SendMessageW(saverList, CB_SETCURSEL, index, 0);
        }
    }

    ConfigureSlider(dialog, IDC_OBJECT_SCALE, kMinimumObjectScalePercent,
                    kMaximumObjectScalePercent, settings.objectScalePercent);
    ConfigureSlider(dialog, IDC_PLAYBACK_SPEED, kMinimumPlaybackSpeedPercent,
                    kMaximumPlaybackSpeedPercent, settings.playbackSpeedPercent);
    UpdatePercentLabel(dialog, IDC_OBJECT_SCALE, IDC_OBJECT_SCALE_VALUE);
    UpdatePercentLabel(dialog, IDC_PLAYBACK_SPEED, IDC_PLAYBACK_SPEED_VALUE);
    CheckDlgButton(dialog, IDC_SHOW_MEMORY_USAGE, settings.showMemoryUsage ? BST_CHECKED : BST_UNCHECKED);
}

bool SaveDialog(HWND dialog)
{
    Settings settings;
    LRESULT selection = SendDlgItemMessageW(dialog, IDC_SAVER, CB_GETCURSEL, 0, 0);
    size_t index = selection >= 0 && static_cast<size_t>(selection) < kSavers.size()
        ? static_cast<size_t>(selection) : 0;
    settings.saver = std::wstring(kSavers[index].filename);
    settings.objectScalePercent = SliderValue(dialog, IDC_OBJECT_SCALE);
    settings.playbackSpeedPercent = SliderValue(dialog, IDC_PLAYBACK_SPEED);
    settings.showMemoryUsage = IsDlgButtonChecked(dialog, IDC_SHOW_MEMORY_USAGE) == BST_CHECKED;
    return settings.Save();
}

INT_PTR CALLBACK DialogProc(HWND dialog, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message) {
    case WM_INITDIALOG:
        InitializeDialog(dialog);
        return TRUE;
    case WM_HSCROLL: {
        int sliderID = GetDlgCtrlID(reinterpret_cast<HWND>(lParam));
        if (sliderID == IDC_OBJECT_SCALE) {
            UpdatePercentLabel(dialog, IDC_OBJECT_SCALE, IDC_OBJECT_SCALE_VALUE);
        } else if (sliderID == IDC_PLAYBACK_SPEED) {
            UpdatePercentLabel(dialog, IDC_PLAYBACK_SPEED, IDC_PLAYBACK_SPEED_VALUE);
        }
        return TRUE;
    }
    case WM_COMMAND:
        switch (LOWORD(wParam)) {
        case IDOK:
            if (!SaveDialog(dialog)) {
                MessageBoxW(dialog, L"The options could not be saved.", L"Slightly After Dark",
                            MB_OK | MB_ICONWARNING);
                return TRUE;
            }
            EndDialog(dialog, IDOK);
            return TRUE;
        case IDCANCEL:
            EndDialog(dialog, IDCANCEL);
            return TRUE;
        }
        break;
    }
    return FALSE;
}

}  // namespace

int RunConfigDialog(HWND owner)
{
    INITCOMMONCONTROLSEX controls = {sizeof(controls), ICC_BAR_CLASSES | ICC_STANDARD_CLASSES};
    InitCommonControlsEx(&controls);
    DialogBoxParamW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDD_CONFIG), owner, DialogProc, 0);
    return 0;
}
