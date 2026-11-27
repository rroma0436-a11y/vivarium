extends RefCounted
## Голос Ніки: записані репліки (assets/sounds/nika/) замість синтезу мови.

const AudioScript := preload("res://scripts/audio.gd")

const LINES := {
	"%s %s ще зелені зачекаймо": "nika/nika_x_x_shche_zeleni_zachekaimo",
	"%s у кошик": "nika/nika_x_u_koshyk",
	"beep привіт": "nika/nika_beep_pryvit",
	"а по обіді біжу в гості до дідуся петра": "nika/nika_a_po_obidi_bizhu_v_hosti_do_didusia_petr",
	"а ти знаєш що за фермою є аеродром в ангарі стоїть жовтий літак і beep уміє ним керувати": "nika/nika_a_ty_znaiesh_shcho_za_fermoiu_ie_aerodro",
	"а що у вас смачненьке": "nika/nika_a_shcho_u_vas_smachnenke",
	"бабусю а що в нас на обід": "nika/nika_babusiu_a_shcho_v_nas_na_obid",
	"бабусю давай я допоможу": "nika/nika_babusiu_davai_ia_dopomozhu",
	"бабусю привіт": "nika/nika_babusiu_pryvit",
	"беру %s": "nika/nika_beru_x",
	"беру кошик": "nika/nika_beru_koshyk",
	"бліда поганка отруйна не чіпаємо": "nika/nika_blida_pohanka_otruina_ne_chipaiemo",
	"брусниці": "nika/nika_brusnytsi",
	"білий гриб": "nika/nika_bilyi_hryb",
	"біме хороший песик": "nika/nika_bime_khoroshyi_pesyk",
	"біп біп друже": "nika/nika_bip_bip_druzhe",
	"вовчі ягоди отруйні не чіпаємо": "nika/nika_vovchi_iahody_otruini_ne_chipaiemo",
	"ворота ангара зачинені натисну кнопку на задній стіні": "nika/nika_vorota_anhara_zachyneni_natysnu_knopku_n",
	"ворота відчиняються": "nika/nika_vorota_vidchyniaiutsia",
	"ворота зачинені спершу кнопка на задній стіні": "nika/nika_vorota_zachyneni_spershu_knopka_na_zadni",
	"ворота зачиняються": "nika/nika_vorota_zachyniaiutsia",
	"візьму кошик тоді назбираю": "nika/nika_vizmu_koshyk_todi_nazbyraiu",
	"гайда гуляти": "nika/nika_haida_huliaty",
	"гоп гоп": "nika/nika_hop_hop",
	"гоп і я там": "nika/nika_hop_i_ia_tam",
	"деревій": "nika/nika_derevii",
	"дзвіночки": "nika/nika_dzvinochky",
	"дзінь дзінь": "nika/nika_dzin_dzin",
	"дивись у небі над округою світяться золоті насінинки чарівного соняшника аж десять": "nika/nika_dyvys_u_nebi_nad_okruhoiu_svitiatsia_zol",
	"добридень дідусю": "nika/nika_dobryden_didusiu",
	"добрий день": "nika/nika_dobryi_den",
	"доброго ранку": "nika/nika_dobroho_ranku",
	"дякую beep": "nika/nika_diakuiu_beep",
	"дякую кладу %s в кошик": "nika/nika_diakuiu_kladu_x_v_koshyk",
	"дякую купила %s": "nika/nika_diakuiu_kupyla_x",
	"дідусю а розкажи казку": "nika/nika_didusiu_a_rozkazhy_kazku",
	"дідусю а що ти робиш": "nika/nika_didusiu_a_shcho_ty_robysh",
	"дідусю допоможи мені на фермі": "nika/nika_didusiu_dopomozhy_meni_na_fermi",
	"дідусю привіт": "nika/nika_didusiu_pryvit",
	"дідусю приходь обідати": "nika/nika_didusiu_prykhod_obidaty",
	"дідусю ти де": "nika/nika_didusiu_ty_de",
	"дідусю ходімо в ліс по гриби": "nika/nika_didusiu_khodimo_v_lis_po_hryby",
	"дідусю я прийшла": "nika/nika_didusiu_ia_pryishla",
	"дідусю я тебе дуже люблю": "nika/nika_didusiu_ia_tebe_duzhe_liubliu",
	"за фермою є аеродром а в ангарі жовтий літак beep уміє ним керувати": "nika/nika_za_fermoiu_ie_aerodrom_a_v_anhari_zhovty",
	"зайчику не бійся": "nika/nika_zaichyku_ne_biisia",
	"залізу в кабіну": "nika/nika_zalizu_v_kabinu",
	"звіробій": "nika/nika_zvirobii",
	"знайшла камінчик": "nika/nika_znaishla_kaminchyk",
	"зранку я ходжу на базар там пахне хлібом і медом": "nika/nika_zranku_ia_khodzhu_na_bazar_tam_pakhne_kh",
	"зірвала %d %s": "nika/nika_zirvala_n_x",
	"конику біжи до мене": "nika/nika_konyku_bizhy_do_mene",
	"конику привіт": "nika/nika_konyku_pryvit",
	"котра година": "nika/nika_kotra_hodyna",
	"кошик далеко лишився біля хати": "nika/nika_koshyk_daleko_lyshyvsia_bilia_khaty",
	"кроком коником": "nika/nika_krokom_konykom",
	"купила сідло й вуздечку віднесу дідусеві в сарай": "nika/nika_kupyla_sidlo_i_vuzdechku_vidnesu_didusev",
	"лисички": "nika/nika_lysychky",
	"м ята": "nika/nika_m_iata",
	"малина": "nika/nika_malyna",
	"маслюки": "nika/nika_masliuky",
	"мені кільце ковбаски": "nika/nika_meni_kiltse_kovbasky",
	"мені хлібину будь ласка": "nika/nika_meni_khlibynu_bud_laska",
	"ммм смачний узвар": "nika/nika_mmm_smachnyi_uzvar",
	"ммм як смачно": "nika/nika_mmm_iak_smachno",
	"мухомор отруйний не чіпаємо": "nika/nika_mukhomor_otruinyi_ne_chipaiemo",
	"на добраніч": "nika/nika_na_dobranich",
	"натисну кнопку воріт": "nika/nika_natysnu_knopku_vorit",
	"не дотягнуся встану й візьму": "nika/nika_ne_dotiahnusia_vstanu_i_vizmu",
	"не дістану": "nika/nika_ne_distanu",
	"не можу підійти до літака": "nika/nika_ne_mozhu_pidiity_do_litaka",
	"немає осідланого коника": "nika/nika_nemaie_osidlanoho_konyka",
	"но о конику": "nika/nika_no_o_konyku",
	"ням ням": "nika/nika_niam_niam",
	"о яка гарна квіточка": "nika/nika_o_iaka_harna_kvitochka",
	"ого як високо": "nika/nika_oho_iak_vysoko",
	"ожина": "nika/nika_ozhyna",
	"ой тут не пройти": "nika/nika_oi_tut_ne_proity",
	"ой у мене лише %d монет": "nika/nika_oi_u_mene_lyshe_n_monet",
	"ой у мене лише %d монет треба %d": "nika/nika_oi_u_mene_lyshe_n_monet_treba_n",
	"ой які льодяники": "nika/nika_oi_iaki_lodianyky",
	"опеньки": "nika/nika_openky",
	"ох і добре": "nika/nika_okh_i_dobre",
	"па па піду додому": "nika/nika_pa_pa_pidu_dodomu",
	"папороть хай росте": "nika/nika_paporot_khai_roste",
	"перелізу": "nika/nika_perelizu",
	"повний кошик %d бабуся зрадіє": "nika/nika_povnyi_koshyk_n_babusia_zradiie",
	"покатаюсь на велосипеді": "nika/nika_pokataius_na_velosypedi",
	"покатаюсь на тракторі": "nika/nika_pokataius_na_traktori",
	"посиджу трошки": "nika/nika_posydzhu_troshky",
	"поставлю кошик тут": "nika/nika_postavliu_koshyk_tut",
	"поїхали": "nika/nika_poikhaly",
	"привіт": "nika/nika_pryvit",
	"привіт бичку тільки не бодайся": "nika/nika_pryvit_bychku_tilky_ne_bodaisia",
	"привіт привіт як добре що ти прийшов": "nika/nika_pryvit_pryvit_iak_dobre_shcho_ty_pryisho",
	"привіт я ніка живу в селі у білій хатці біля площі": "nika/nika_pryvit_ia_nika_zhyvu_v_seli_u_bilii_khat",
	"приземлились ох і гарно було": "nika/nika_pryzemlylys_okh_i_harno_bulo",
	"приїхали в грибний ліс злізаю і по гриби": "nika/nika_pryikhaly_v_hrybnyi_lis_zlizaiu_i_po_hry",
	"підберезник": "nika/nika_pidbereznyk",
	"підосичник": "nika/nika_pidosychnyk",
	"піду в ліс по гриби та ягоди": "nika/nika_pidu_v_lis_po_hryby_ta_iahody",
	"піду до дідуся петра": "nika/nika_pidu_do_didusia_petra",
	"піду на базар за річку": "nika/nika_pidu_na_bazar_za_richku",
	"рижики": "nika/nika_ryzhyky",
	"риссю но о": "nika/nika_ryssiu_no_o",
	"розкажи жарт": "nika/nika_rozkazhy_zhart",
	"ромашка": "nika/nika_romashka",
	"сироїжки": "nika/nika_syroizhky",
	"скільки коштують яблучка": "nika/nika_skilky_koshtuiut_iabluchka",
	"смакота": "nika/nika_smakota",
	"спершу треба взяти кошик він біля хати": "nika/nika_spershu_treba_vziaty_koshyk_vin_bilia_kh",
	"суниці": "nika/nika_sunytsi",
	"сьогодні тут уже все зібрали": "nika/nika_sohodni_tut_uzhe_vse_zibraly",
	"сідаю за штурвал": "nika/nika_sidaiu_za_shturval",
	"ти мій друг": "nika/nika_ty_mii_druh",
	"тримаюсь міцно": "nika/nika_trymaius_mitsno",
	"трошки полежу": "nika/nika_troshky_polezhu",
	"у небі світяться золоті насінинки збери їх на літаку": "nika/nika_u_nebi_svitiatsia_zoloti_nasinynky_zbery",
	"ура а": "nika/nika_ura_a",
	"усе купила тепер додому": "nika/nika_use_kupyla_teper_dodomu",
	"усі десять дідусь посадив їх біля хати і виріс чарівний соняшник": "nika/nika_usi_desiat_didus_posadyv_ikh_bilia_khaty",
	"ух оце так політ пропелер аж дзижчить": "nika/nika_ukh_otse_tak_polit_propeler_azh_dzyzhchy",
	"хороший коник розумничок": "nika/nika_khoroshyi_konyk_rozumnychok",
	"хто тут мій пухнастик": "nika/nika_khto_tut_mii_pukhnastyk",
	"це далеко підійду ближче": "nika/nika_tse_daleko_pidiidu_blyzhche",
	"це я сховаю в кишеньку": "nika/nika_tse_ia_skhovaiu_v_kyshenku",
	"ціп ціп ціп": "nika/nika_tsip_tsip_tsip",
	"чебрець": "nika/nika_chebrets",
	"чорниці": "nika/nika_chornytsi",
	"що робити далі": "nika/nika_shcho_robyty_dali",
	"що ти вмієш": "nika/nika_shcho_ty_vmiiesh",
	"я принесла пиріжків": "nika/nika_ia_prynesla_pyrizhkiv",
	"я стрибаю": "nika/nika_ia_strybaiu",
	"як справи": "nika/nika_iak_spravy",
	"як справи beep": "nika/nika_iak_spravy_beep",
	"як тут затишно": "nika/nika_iak_tut_zatyshno",
	"яке смачне молочко": "nika/nika_iake_smachne_molochko",
	"який ти гарний конику": "nika/nika_iakyi_ty_harnyi_konyku",
	"іди но сюди коником покатаюсь": "nika/nika_idy_no_siudy_konykom_pokataius",
	"іду до бабусі": "nika/nika_idu_do_babusi",
	"іду до дідуся": "nika/nika_idu_do_didusia",
	"іду до літака": "nika/nika_idu_do_litaka",
	"іду додому": "nika/nika_idu_dodomu",
	"іду на базар": "nika/nika_idu_na_bazar",
	"іду по кошик": "nika/nika_idu_po_koshyk",
	"їдемо": "nika/nika_idemo",
	"їду в ліс по гриби та ягоди": "nika/nika_idu_v_lis_po_hryby_ta_iahody",
}
const ALIAS := {"но о коником": "но о конику"}

static var _clean: RegEx
static var _tpl: Array = []          # [RegEx, ключ] — репліки з %d / %s


static func key(text: String) -> String:
	if _clean == null:
		_clean = RegEx.create_from_string("[^0-9a-zа-яёіїєґ%]+")
	var t := text.replace("z-z-z", "").replace(char(0x301), "").to_lower()
	return _clean.sub(t, " ", true).strip_edges()


static func _build() -> void:
	if not _tpl.is_empty():
		return
	for k in LINES:
		if "%" in k:
			var r := "^" + String(k).replace("%d", "(\\d+)").replace("%s", "(.+?)") + "$"
			_tpl.append([RegEx.create_from_string(r), k])


static func ids_for(text: String, prefix := false) -> Array:
	var k := key(text)
	if k == "":
		return []
	k = String(ALIAS.get(k, k))
	if LINES.has(k):
		return [LINES[k]]
	_build()
	for t in _tpl:
		var m: RegExMatch = (t[0] as RegEx).search(k)
		if m == null:
			continue
		var tk := String(t[1])
		var vals: Array = []
		for i in range(1, m.get_group_count() + 1):
			var v := m.get_string(i)
			if LINES.has(v):
				vals.append(LINES[v])
		return vals + [LINES[tk]] if tk.begins_with("%") else [LINES[tk]] + vals
	if prefix:
		var best := ""
		for lk in LINES:
			var s := String(lk)
			if s.count(" ") >= 3 and not "%" in s and (k + " ").begins_with(s + " ") and s.length() > best.length():
				best = s
		if best != "":
			return [LINES[best]]
	return []


static func play(text: String, prefix := false) -> bool:
	var a = AudioScript.inst
	if a == null or not is_instance_valid(a):
		return false
	var ids := ids_for(text, prefix)
	if ids.is_empty():
		return false
	a.voice(ids)
	return true
