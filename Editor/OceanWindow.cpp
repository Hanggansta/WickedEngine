#include "stdafx.h"
#include "OceanWindow.h"


OceanWindow::OceanWindow(wiGUI* gui) :GUI(gui)
{
	assert(GUI && "Invalid GUI!");

	float screenW = (float)wiRenderer::GetDevice()->GetScreenWidth();
	float screenH = (float)wiRenderer::GetDevice()->GetScreenHeight();


	oceanWindow = new wiWindow(GUI, "Ocean Window");
	oceanWindow->SetSize(XMFLOAT2(700, 380));
	GUI->AddWidget(oceanWindow);

	float x = 200;
	float y = 0;
	float inc = 35;

	enabledCheckBox = new wiCheckBox("Ocean simulation enabled: ");
	enabledCheckBox->SetPos(XMFLOAT2(x, y += inc));
	enabledCheckBox->OnClick([&](wiEventArgs args) {
		wiRenderer::SetOceanEnabled(args.bValue, params);
	});
	enabledCheckBox->SetCheck(wiRenderer::GetOcean() != nullptr);
	oceanWindow->AddWidget(enabledCheckBox);


	patchSizeSlider = new wiSlider(1, 2000, 1000, 100000, "Patch size: ");
	patchSizeSlider->SetSize(XMFLOAT2(100, 30));
	patchSizeSlider->SetPos(XMFLOAT2(x, y += inc));
	patchSizeSlider->SetValue(params.patch_length);
	patchSizeSlider->OnSlide([&](wiEventArgs args) {
		params.patch_length = args.fValue;
		wiRenderer::SetOceanEnabled(enabledCheckBox->GetCheck(), params);
	});
	oceanWindow->AddWidget(patchSizeSlider);

	waveAmplitudeSlider = new wiSlider(0, 100, 1000, 100000, "Wave amplitude: ");
	waveAmplitudeSlider->SetSize(XMFLOAT2(100, 30));
	waveAmplitudeSlider->SetPos(XMFLOAT2(x, y += inc));
	waveAmplitudeSlider->SetValue(params.wave_amplitude);
	waveAmplitudeSlider->OnSlide([&](wiEventArgs args) {
		params.wave_amplitude = args.fValue;
		wiRenderer::SetOceanEnabled(enabledCheckBox->GetCheck(), params);
	});
	oceanWindow->AddWidget(waveAmplitudeSlider);

	choppyScaleSlider = new wiSlider(0, 10, 1000, 100000, "Choppiness: ");
	choppyScaleSlider->SetSize(XMFLOAT2(100, 30));
	choppyScaleSlider->SetPos(XMFLOAT2(x, y += inc));
	choppyScaleSlider->SetValue(params.choppy_scale);
	choppyScaleSlider->OnSlide([&](wiEventArgs args) {
		params.choppy_scale = args.fValue;
		wiRenderer::SetOceanEnabled(enabledCheckBox->GetCheck(), params);
	});
	oceanWindow->AddWidget(choppyScaleSlider);

	windDependencySlider = new wiSlider(0, 1, 1000, 100000, "Wind dependency: ");
	windDependencySlider->SetSize(XMFLOAT2(100, 30));
	windDependencySlider->SetPos(XMFLOAT2(x, y += inc));
	windDependencySlider->SetValue(params.wind_dependency);
	windDependencySlider->OnSlide([&](wiEventArgs args) {
		params.wind_dependency = args.fValue;
		wiRenderer::SetOceanEnabled(enabledCheckBox->GetCheck(), params);
	});
	oceanWindow->AddWidget(windDependencySlider);

	timeScaleSlider = new wiSlider(0, 4, 1000, 100000, "Time scale: ");
	timeScaleSlider->SetSize(XMFLOAT2(100, 30));
	timeScaleSlider->SetPos(XMFLOAT2(x, y += inc));
	timeScaleSlider->SetValue(params.time_scale);
	timeScaleSlider->OnSlide([&](wiEventArgs args) {
		params.time_scale = args.fValue;
		wiRenderer::SetOceanEnabled(enabledCheckBox->GetCheck(), params);
	});
	oceanWindow->AddWidget(timeScaleSlider);

	heightSlider = new wiSlider(-100, 100, 0, 100000, "Water level: ");
	heightSlider->SetSize(XMFLOAT2(100, 30));
	heightSlider->SetPos(XMFLOAT2(x, y += inc));
	heightSlider->SetValue(0);
	heightSlider->OnSlide([&](wiEventArgs args) {
		if (wiRenderer::GetOcean() != nullptr)
			wiRenderer::GetOcean()->waterHeight = args.fValue;
	});
	oceanWindow->AddWidget(heightSlider);

	detailSlider = new wiSlider(1, 10, 0, 9, "Surface Detail: ");
	detailSlider->SetSize(XMFLOAT2(100, 30));
	detailSlider->SetPos(XMFLOAT2(x, y += inc));
	detailSlider->SetValue(4);
	detailSlider->OnSlide([&](wiEventArgs args) {
		if (wiRenderer::GetOcean() != nullptr)
			wiRenderer::GetOcean()->surfaceDetail = (uint32_t)args.iValue;
	});
	oceanWindow->AddWidget(detailSlider);

	toleranceSlider = new wiSlider(1, 10, 0, 1000, "Displacement Tolerance: ");
	toleranceSlider->SetSize(XMFLOAT2(100, 30));
	toleranceSlider->SetPos(XMFLOAT2(x, y += inc));
	toleranceSlider->SetValue(2);
	toleranceSlider->OnSlide([&](wiEventArgs args) {
		if (wiRenderer::GetOcean() != nullptr)
			wiRenderer::GetOcean()->surfaceDisplacementTolerance = args.fValue;
	});
	oceanWindow->AddWidget(toleranceSlider);


	colorPicker = new wiColorPicker(GUI, "Water Color");
	colorPicker->SetPos(XMFLOAT2(380, 30));
	colorPicker->RemoveWidgets();
	colorPicker->SetVisible(true);
	colorPicker->SetEnabled(true);
	colorPicker->OnColorChanged([&](wiEventArgs args) {
		if (wiRenderer::GetOcean() != nullptr)
			wiRenderer::GetOcean()->waterColor = XMFLOAT3(powf(args.color.x, 1.f / 2.2f), powf(args.color.y, 1.f / 2.2f), powf(args.color.z, 1.f / 2.2f));
	});
	oceanWindow->AddWidget(colorPicker);


	oceanWindow->Translate(XMFLOAT3(800, 50, 0));
	oceanWindow->SetVisible(false);
}


OceanWindow::~OceanWindow()
{
	oceanWindow->RemoveWidgets(true);
	GUI->RemoveWidget(oceanWindow);
	SAFE_DELETE(oceanWindow);
}