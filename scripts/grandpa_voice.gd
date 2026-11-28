extends RefCounted
## Голос дідуся Петра: записані репліки (assets/sounds/grandpa/); чого немає в записах — системним голосом.

const AudioScript := preload("res://scripts/audio.gd")
const NV := preload("res://scripts/nika_voice.gd")

const LINES := {
	"будка ціла бімові тепло": "grandpa/gp_budka_tsila_bimovi_teplo",
	"будуть млинці": "grandpa/gp_budut_mlyntsi",
	"вже виходжу": "grandpa/gp_vzhe_vykhodzhu",
	"вода в криниці чиста холодна": "grandpa/gp_voda_v_krynytsi_chysta_kholodna",
	"візьму кошика й поїду конем у ліс по гриби": "grandpa/gp_vizmu_koshyka_i_poidu_konem_u_lis_po_hryby",
	"гайда в ліс": "grandpa/gp_haida_v_lis",
	"гайда до млина на пагорбі": "grandpa/gp_haida_do_mlyna_na_pahorbi",
	"гайда на ставок": "grandpa/gp_haida_na_stavok",
	"галю ось рибка звари юшки": "grandpa/gp_haliu_os_rybka_zvary_iushky",
	"галю рибку на ґанку лишаю на юшку": "grandpa/gp_haliu_rybku_na_ganku_lyshaiu_na_iushku",
	"гарна їзда везімо коня додому": "grandpa/gp_harna_izda_vezimo_konia_dodomu",
	"готово плуг на возі": "grandpa/gp_hotovo_pluh_na_vozi",
	"дайте паляницю й булочок": "grandpa/gp_daite_palianytsiu_i_bulochok",
	"далі пішки через місток": "grandpa/gp_dali_pishky_cherez_mistok",
	"добре скоро прийду хай ставлять борщ": "grandpa/gp_dobre_skoro_pryidu_khai_stavliat_borshch",
	"доброго ранку": "grandpa/gp_dobroho_ranku",
	"додому коню": "grandpa/gp_dodomu_koniu",
	"додому червоненький": "grandpa/gp_dodomu_chervonenkyi",
	"дякую будьте здорові": "grandpa/gp_diakuiu_budte_zdorovi",
	"дякую коню іди відпочивай": "grandpa/gp_diakuiu_koniu_idy_vidpochyvai",
	"ех плуга в нас нема": "grandpa/gp_ekh_pluha_v_nas_nema",
	"ех трактора в нас нема": "grandpa/gp_ekh_traktora_v_nas_nema",
	"зараз доберуся почекай трохи": "grandpa/gp_zaraz_doberusia_pochekai_trokhy",
	"зараз запряжу коня і поїдемо бабо": "grandpa/gp_zaraz_zapriazhu_konia_i_poidemo_babo",
	"здоров був %s як там на фермі": "grandpa/gp_zdorov_buv_x_iak_tam_na_fermi",
	"зніму плуга": "grandpa/gp_znimu_pluha",
	"зніму плуга з воза": "grandpa/gp_znimu_pluha_z_voza",
	"клює": "grandpa/gp_kliuie",
	"кури здорові слава богу": "grandpa/gp_kury_zdorovi_slava_bohu",
	"курочки вже в курнику добре": "grandpa/gp_kurochky_vzhe_v_kurnyku_dobre",
	"кінь уже запряжений": "grandpa/gp_kin_uzhe_zapriazhenyi",
	"ловись рибко велика й маленька": "grandpa/gp_lovys_rybko_velyka_i_malenka",
	"ліс далеко а грибів нема": "grandpa/gp_lis_daleko_a_hrybiv_nema",
	"мели млинку борошенце": "grandpa/gp_mely_mlynku_boroshentse",
	"мені кільце ковбаски будь ласка": "grandpa/gp_meni_kiltse_kovbasky_bud_laska",
	"назбирав %d буде на вечерю": "grandpa/gp_nazbyrav_n_bude_na_vecheriu",
	"назбирав %d грибочків": "grandpa/gp_nazbyrav_n_hrybochkiv",
	"насиплю зерна у відро": "grandpa/gp_nasypliu_zerna_u_vidro",
	"но о коню гайда на поле": "grandpa/gp_no_o_koniu_haida_na_pole",
	"но о коню додому": "grandpa/gp_no_o_koniu_dodomu",
	"но о мій коню ходи сюди": "grandpa/gp_no_o_mii_koniu_khody_siudy",
	"но о на ринок": "grandpa/gp_no_o_na_rynok",
	"ну онучку кермуй конем я пасажиром": "grandpa/gp_nu_onuchku_kermui_konem_ia_pasazhyrom",
	"ну червоненький гайда в ліс": "grandpa/gp_nu_chervonenkyi_haida_v_lis",
	"ну червоненький поїхали": "grandpa/gp_nu_chervonenkyi_poikhaly",
	"оремо": "grandpa/gp_oremo",
	"ось і борошно будуть пиріжки": "grandpa/gp_os_i_boroshno_budut_pyrizhky",
	"ось і вдома": "grandpa/gp_os_i_vdoma",
	"от і добре візьму в вас соломки": "grandpa/gp_ot_i_dobre_vizmu_v_vas_solomky",
	"ото гарно зорали": "grandpa/gp_oto_harno_zoraly",
	"ото гарно зорали конем": "grandpa/gp_oto_harno_zoraly_konem",
	"ох зачитався піду вже спати добраніч": "grandpa/gp_okh_zachytavsia_pidu_vzhe_spaty_dobranich",
	"ох і гарні ж соняшники ростуть": "grandpa/gp_okh_i_harni_zh_soniashnyky_rostut",
	"ох і смачна в нас вода": "grandpa/gp_okh_i_smachna_v_nas_voda",
	"ох і смачний узвар": "grandpa/gp_okh_i_smachnyi_uzvar",
	"ох і я тебе люблю": "grandpa/gp_okh_i_ia_tebe_liubliu",
	"плуга на віз": "grandpa/gp_pluha_na_viz",
	"повний кошик гостинців": "grandpa/gp_povnyi_koshyk_hostyntsiv",
	"подрімаю трішки": "grandpa/gp_podrimaiu_trishky",
	"покладу плуга на віз": "grandpa/gp_pokladu_pluha_na_viz",
	"пора спати": "grandpa/gp_pora_spaty",
	"посіяв рости пшеничко колосиста": "grandpa/gp_posiiav_rosty_pshenychko_kolosysta",
	"почім куме сокири подивлюся поки баба купує": "grandpa/gp_pochim_kume_sokyry_podyvliusia_poky_baba_kup",
	"поїду в млин змелю пшениці": "grandpa/gp_poidu_v_mlyn_zmeliu_pshenytsi",
	"поїду на ринок куплю чогось смачненького": "grandpa/gp_poidu_na_rynok_kupliu_chohos_smachnenkoho",
	"поїду на ставок рибку ловити": "grandpa/gp_poidu_na_stavok_rybku_lovyty",
	"поїду на ферму провідаю хлопців і візьму соломи": "grandpa/gp_poidu_na_fermu_providaiu_khloptsiv_i_vizmu_s",
	"поїду орати поле конем": "grandpa/gp_poidu_oraty_pole_konem",
	"поїду сіяти пшеницю": "grandpa/gp_poidu_siiaty_pshenytsiu",
	"піду запрягати коня": "grandpa/gp_pidu_zapriahaty_konia",
	"піду поорю поле": "grandpa/gp_pidu_pooriu_pole",
	"піду почитаю книжку": "grandpa/gp_pidu_pochytaiu_knyzhku",
	"розпрягаю відпочивай коню": "grandpa/gp_rozpriahaiu_vidpochyvai_koniu",
	"соломки набрав додому": "grandpa/gp_solomky_nabrav_dodomu",
	"сьогодні все вже позбирали": "grandpa/gp_sohodni_vse_vzhe_pozbyraly",
	"сьогодні гриби вже позбирали": "grandpa/gp_sohodni_hryby_vzhe_pozbyraly",
	"сіна в сараї вистачить на всю зиму": "grandpa/gp_sina_v_sarai_vystachyt_na_vsiu_zymu",
	"сію вію посіваю": "grandpa/gp_siiu_viiu_posivaiu",
	"тпру злазь бабо приїхали": "grandpa/gp_tpru_zlaz_babo_pryikhaly",
	"тпру розпряжу відпочинь коню": "grandpa/gp_tpru_rozpriazhu_vidpochyn_koniu",
	"тпру сідай бабо поїхали": "grandpa/gp_tpru_sidai_babo_poikhaly",
	"тпру у стій запрягаю": "grandpa/gp_tpru_u_stii_zapriahaiu",
	"треба б граблі полагодити": "grandpa/gp_treba_b_hrabli_polahodyty",
	"три рибки буде юшка": "grandpa/gp_try_rybky_bude_iushka",
	"хай плуг постоїть біля садка": "grandpa/gp_khai_pluh_postoit_bilia_sadka",
	"хлопців не видно мабуть обідають": "grandpa/gp_khloptsiv_ne_vydno_mabut_obidaiut",
	"ходи коню до плуга": "grandpa/gp_khody_koniu_do_pluha",
	"щось ринок сьогодні порожній": "grandpa/gp_shchos_rynok_sohodni_porozhnii",
	"я вдома в хаті заходь ніко": "grandpa/gp_ia_vdoma_v_khati_zakhod_niko",
	"я вже в хаті": "grandpa/gp_ia_vzhe_v_khati",
	"я вже сплю": "grandpa/gp_ia_vzhe_spliu",
	"я вже читаю онучку": "grandpa/gp_ia_vzhe_chytaiu_onuchku",
	"я й так на подвір ї": "grandpa/gp_ia_i_tak_na_podvir_i",
	"я тут %s скажи ніці хай не хвилюється": "grandpa/gp_ia_tut_x_skazhy_nitsi_khai_ne_khvyliuietsia",
	"іду вже іду спати": "grandpa/gp_idu_vzhe_idu_spaty",
	"іду іду": "grandpa/gp_idu_idu",
}

static var _tpl: Array = []          # [RegEx, ключ] — репліки з %d / %s


static func _build() -> void:
	if not _tpl.is_empty():
		return
	for k in LINES:
		if "%" in k:
			var r := "^" + String(k).replace("%d", "(\\d+)").replace("%s", "(.+?)") + "$"
			_tpl.append([RegEx.create_from_string(r), k])


static func ids_for(text: String, prefix := false) -> Array:
	var k := NV.key(text)
	if k == "":
		return []
	if LINES.has(k):
		return [LINES[k]]
	_build()
	for t in _tpl:
		if (t[0] as RegEx).search(k) != null:
			return [LINES[String(t[1])]]
	if prefix:
		var best := ""
		for lk in LINES:
			var s := String(lk)
			if s.count(" ") >= 3 and not "%" in s and (k + " ").begins_with(s + " ") and s.length() > best.length():
				best = s
		if best != "":
			return [LINES[best]]
	return []


static func play(text: String, prefix := true) -> bool:
	var a = AudioScript.inst
	if a == null or not is_instance_valid(a):
		return false
	var ids := ids_for(text, prefix)
	if ids.is_empty():
		return false
	a.voice(ids)
	return true
