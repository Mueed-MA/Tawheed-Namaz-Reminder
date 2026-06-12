import 'package:flutter/material.dart';

import 'dua_item.dart';
import 'dua_detail_screen.dart';

class DuaScreen extends StatelessWidget {
  const DuaScreen({super.key});

  // Keep this list empty so you can add items one by one.
  static final List<DuaItem> _duas = <DuaItem>[
    DuaItem(
      title: 'Sone ki Dua',
      arabic: 'اَللّٰهُمَّ بِاسْمِكَ اَمُوْتُ وَاَحْيَا',

      romanEnglish: 'Allaahumma bismika amootu wa ahyaa',
      romanTelugu: 'అల్లాహుమ్మ బిస్మిక అమూతు వ అహ్-యా',
    ),
    DuaItem(
      title: 'Neend se uthne ki Dua',
      arabic:
          'اَلْحَمْدُ لِلّٰهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ',

      romanEnglish:
          'Alhamdu lillaahil lazii ahyaanaa ba’da maa amaatanaa wa ilaihin nushoor.',
      romanTelugu:
          "అల్‌హమ్దు లిల్లాహిల్లజీ అహ్ యానా బఅ'ద మా అమాతనా వ ఇలైహిన్నుశూర్",
      arabicFontFamily: 'MuhammadiQuranic',
    ),
    DuaItem(
      title: 'Achha Khwab (Good Dream) ki Dua',
      arabic: 'الْحَمْدُ لِلَّهِ',
      romanEnglish: 'Alhamdulillaah',
      romanTelugu: 'అల్హమ్దులిల్లాహ్',
    ),
    DuaItem(
      title: 'Bura Khwab (Bad Dream) ki Dua',
      arabic: 'اَعُوْذُ بِاللّٰهِ مِنَ الشَّيْطَانِ الرَّجِيْمِ',
      romanEnglish: 'Auzu billaahi minash shaitaanir rajeem',
      romanTelugu: 'అఊజు బిల్లాహి మినష్ షైతానిర్ రజీమ్',
    ),
    DuaItem(
      title: 'Hifazat ki Dua (Subah aur Shaam)',
      arabic:
          'بِسْمِ اللّٰهِ الَّذِىْ لَا يَضُرُّ مَعَ اسْمِهٖ شَىْءٌ فِى الْاَرْضِ وَلَا فِى السَّمَآءِ وَهُوَ السَّمِيْعُ الْعَلِيْمُ',

      romanEnglish:
          'Bismillaahil-lazee laa yazurru ma‘asmihi shai’un fil arzi wa laa fis samaa’i wa huwas Samee‘ul Aleem',
      romanTelugu:
          "బిస్మిల్లాహిల్లజీ లా యజుర్రు మఅస్మిహీ షయ్ ఉన్ ఫిల్ అర్జి వ లా ఫిస్ సమాఈ వ హువస్ సమీఉల్ అలీమ్",
      arabicFontFamily: 'MuhammadiQuranic',
    ),
    DuaItem(
      title: 'Bait-ul-Khala (toilet) mein jaane ki Dua',
      arabic: """'بِسْمِ اللّٰهِ
 اللَّهُمَّ إِنِّي أَعُوذُ بِكَ مِنَ الْخُبُثِ وَالْخَبَائِثِ'""",

      romanEnglish:
          'Bismillaahi, allaahumma  inni auoozu bika minal khubusi wal khabaa-is',
      romanTelugu:
          'బిస్మిల్లాహి అల్లాహుమ్మా ఇన్నీ అఊజు బిక మినల్ ఖుబుసి వల్ ఖబా-ఇస్',
      arabicFontFamily: 'MuhammadiQuranic',
    ),
    DuaItem(
      title: 'Bait-ul-Khala se bahar aane ki Dua',
      arabic:
          'غُفْرَانَكَ اَلْحَمْدُ لِلّٰهِ الَّذِىْ اَذْهَبَ عَنِّى الْاَذٰى وَعَافَانِىْ',

      romanEnglish:
          'Ghufraanaka Alhamdu lillaahil-lazee azhaba ‘annil azaa wa ‘aafaanee',
      romanTelugu:
          'ఘుఫ్రానక అల్‌హమ్దు లిల్లాహిల్లజీ అజ్ హబ అన్నిల్ అజా వ ఆఫానీ',
      arabicFontFamily: 'MuhammadiQuranic',
    ),
    DuaItem(
      title: 'Ghar se bahar nikalne ki Dua',
      arabic:
          'بِسْمِ اللّٰهِ تَوَكَّلْتُ عَلَى اللّٰهِ لَا حَوْلَ وَلَا قُوَّةَ اِلَّا بِاللّٰهِ',

      romanEnglish:
          'Bismillaahi tawakkaltu ‘alal-laahi laa hawla wa laa quwwata illaa billaah',
      romanTelugu:
          'బిస్మిల్లాహి తవక్కల్తు అలల్లాహి లా హౌల వ లా ఖువ్వత ఇల్లా బిల్లాహ్',
      arabicFontFamily: 'MuhammadiQuranic',
    ),
    DuaItem(
      title: 'Ghar mein dakhil hone ki Dua',
      arabic:
          'اَللّٰهُمَّ اِنِّىْ اَسْئَلُكَ خَيْرَ الْمَوْلَجِ وَخَيْرَ الْمَخْرَجِ بِسْمِ اللّٰهِ وَلَجْنَا وَبِسْمِ اللّٰهِ خَرَجْنَا وَعَلَى اللّٰهِ رَبِّنَا تَوَكَّلْنَا',

      romanEnglish:
          'Allaahumma inni as’aluka khairal maulaji wa khairal makhraji bismillaahi walajnaa wa bismillaahi kharajnaa wa ‘alallaahi Rabbinaa tawakkalnaa',
      romanTelugu:
          'అల్లాహుమ్మ ఇన్నీ అస్అలుక ఖైరల్ మౌలజి వ ఖైరల్ మఖ్రజి బిస్మిల్లాహి వలజ్నా వ బిస్మిల్లాహి ఖరజ్నా వ అలల్లాహి రబ్బినా తవక్కల్నా',
    ),
    DuaItem(
      title: 'Azan ke Baad ki Dua',
      arabic:
          'اَللّٰهُمَّ رَبَّ هٰذِهِ الدَّعْوَةِ التَّامَّةِ وَالصَّلَاةِ الْقَائِمَةِ اٰتِ مُحَمَّدَنِ الْوَسِيْلَةَ وَالْفَضِيْلَةَ وَابْعَثْهُ مَقَامًا مَّحْمُوْدَنِ الَّذِىْ وَعَدْتَّهٗ اِنَّكَ لَا تُخْلِفُ الْمِيْعَادَ',
      romanEnglish:
          'Allaahumma rabba haazihid-da‘watit-taammati wassalaatil qaa’imati aati Muhammadanil waseelata wal fazeelata wab‘as-hu maqaamam mahmoodanil-lazee wa‘ad-tahu innaka laa tukhliful mee‘aad',
      romanTelugu:
          'అల్లాహుమ్మ రబ్బ హాజిహిద్ దవతిత్-తామ్మతివస్సలాతిల్ ఖాఇమతి ఆతి ముహమ్మదనిల్ వసీలత వల్ ఫజీలత వబ్అస్-హు మఖామమ్ మహ్-మూదనిల్-లజీ వ‘అద్-తహు ఇన్నక లా తుఖ్లిఫుల్ మీఆద్',
    ),
    DuaItem(
      title: 'Masjid mein dakhil hone ki Dua',
      arabic: 'اَللّٰهُمَّ افْتَحْ لِىْ اَبْوَابَ رَحْمَتِكَ',

      romanEnglish: 'Alla-hummaf tah-lee ab-waaba rahmatika',
      romanTelugu: 'ఆల్లహుమ్మఫ్ తహ్లీ అబ్-వాబ రహ్మతిక',
    ),
    DuaItem(
      title: 'Masjid se nikalne ki Dua',
      arabic: 'اَللّٰهُمَّ اِنِّىْ اَسْئَلُكَ مِنْ فَضْلِكَ وَرَحْمَتِكَ',

      romanEnglish: 'Allahumma inni as’aluka min fazlika wa rahmatika',
      romanTelugu: 'అల్లాహుమ్మ ఇన్నీ అస్అలుక మిన్ ఫజ్లిక వ రహ్మతిక',
    ),
    DuaItem(
      title: 'Wazu se pehle ki Dua',
      arabic:
          'بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيْمِ (or)بِسْمِ اللّٰهِ وَالْحَمْدُ لِلّٰهِ عَلٰى دِيْنِ الْاِسْلَامِ',

      romanEnglish:
          "Bismillaahir Rahmaanir Raheem (or ) Bismillaahi wal hamdu lillaahi ‘alaa deenil Islaam",
      romanTelugu:
          'బిస్మిల్లాహిర్ రహ్మానిర్ రహీమ్ (or ) బిస్మిల్లాహి వల్ హమ్దు లిల్లాహి అలా దీనిల్ ఇస్లామ్',
    ),
    DuaItem(
      title: 'Wazu ke baad ki Dua',
      arabic:
          'اَشْهَدُ اَنْ لَّاۤ اِلٰهَ اِلَّا اللّٰهُ وَحْدَهٗ لَا شَرِيْكَ لَهٗ وَاَشْهَدُ اَنَّ مُحَمَّدًا عَبْدُهٗ وَرَسُوْلُهٗ\nاَللّٰهُمَّ اجْعَلْنِىْ مِنَ التَّوَّابِيْنَ وَاجْعَلْنِىْ مِنَ الْمُتَطَهِّرِيْنَ',

      romanEnglish:
          """'Ash-hadu allaa ilaaha illallaahu wahdahu laa shareeka lahu wa ash-hadu anna Muhammadan ‘abduhu wa Rasooluhu Allahummaj ‘alnee minat tawwaabeena waj ‘alnee minal mutatah hireen'""",
      romanTelugu:
          'అష్-హదు అల్లా ఇలాహ ఇల్లల్లాహు వహ్-దహు  లా షరీక లహు వ అష్-హదు అన్న ముహమ్మదన్ అబ్-దుహు  వ రసూలుహు\nఅల్లాహుమ్మజ్ అల్‌నీ మినత్ -తవ్వాబీన వజ్ అల్‌నీ మినల్ ముతతహ్హిరీన్',
    ),
    DuaItem(
      title: 'Khane se pehle ki Dua',
      arabic:
          """' اَللّٰهُمَّ بَارِكْ لَنَا فِيْمَا رَزَقْتَنَا وَارْزُقْنَا خَيْرًا مِّنْهُ
بِسْمِ اللّٰهِ وَعَلٰى بَرَكَةِ اللّٰهِ'""",

      romanEnglish:
          '''"Allaahumma baarik lanaa feemaa razaqtanaa warzuqnaa khairam minhu
Bismillaahi wa ‘alaa barakatillaah"''',
      romanTelugu:
          """'అల్లాహుమ్మ బారిక్ లనా ఫీమా రజఖ్తనా వర్‌జుఖ్నా ఖైరమ్ మిన్హు
బిస్మిల్లాహి వ అలా బరకతిల్లాహ్'""",
    ),
    DuaItem(
      title: 'Khane ke baad ki Dua (Mashhoor)',
      arabic:
          'اَلْحَمْدُ لِلّٰهِ الَّذِىْ اَطْعَمَنَا وَسَقَانَا وَجَعَلَنَا مِنَ الْمُسْلِمِيْنَ',

      romanEnglish:
          "Alhamdu lillaahil-lazee at‘amanaa wa saqaanaa wa ja‘alanaa minal muslimeen",
      romanTelugu:
          'అల్-హమ్దు లిల్లాహిల్లజీ అత్-ఆమనా వసఖానా వజ అలనా మినల్ ముస్లిమీన్',
    ),
    DuaItem(
      title: 'Dawat dene wale ke liye Dua',
      arabic: 'اَللّٰهُمَّ اَطْعِمْ مَنْ اَطْعَمَنِىْ وَاسْقِ مَنْ سَقَانِىْ',

      romanEnglish: "Allaahumma at‘im man at‘amanee wasqi man saqaanee",
      romanTelugu: 'అల్లాహుమ్మ అత్‌ఇమ్ మన్ అత్‌అమనీ వ అస్ఖి మన్ సఖానీ',
    ),
    DuaItem(
      title: 'Doodh Peene ki Dua',
      arabic: 'اَللّٰهُمَّ بَارِكْ لَنَا فِيْهِ وَزِدْنَا مِنْهُ',
      romanEnglish: 'Allaahumma baarik lanaa feehi wa zidnaa minhu',
      romanTelugu: 'అల్లాహుమ్మ బారిక్ లనా ఫీహి వ జిద్నా మిన్హు',
    ),
    DuaItem(
      title: 'Salam Karne ki Dua',
      arabic: 'اَلسَّلَامُ عَلَيْكُمْ وَرَحْمَةُ اللّٰهِ وَبَرَكَاتُهٗ',
      romanEnglish: "Assalaamu ‘Alaikum wa Rahmatullaahi wa Barakaatuhu",
      romanTelugu: 'అస్సలాము అలైకుమ్ వ రహ్మతుల్లాహి వ బరకాతుహు',
    ),
    DuaItem(
      title: 'Salam ka Jawab ki Dua',
      arabic: 'وَعَلَيْكُمُ السَّلَامُ وَرَحْمَةُ اللّٰهِ وَبَرَكَاتُهٗ',
      romanEnglish: "Wa ‘Alaikumus Salaamu wa Rahmatullaahi wa Barakaatuhu",
      romanTelugu: 'వ అలైకుముస్సలాము వ రహ్మతుల్లాహి వ బరకాతుహు',
    ),
    DuaItem(
      title: 'Kapde Pehenne ki Dua',
      arabic:
          'اَلْحَمْدُ لِلّٰهِ الَّذِىْ كَسَانِىْ هٰذَا، وَرَزَقَنِيْهِ مِنْ غَيْرِ حَوْلٍ مِّنِّىْ، وَلَا قُوَّةٍ',
      romanEnglish:
          'Alhamdu lillaahil-lazee kasaanee haazaa, wa razaqaneehi min ghairi hawlim minnee, wa laa quwwah',
      romanTelugu:
          'అల్‌హమ్దు లిల్లాహిల్లజీ కసానీ హాజా, వ రజఖానీహీ మిన్ ఘైరి హౌలిమ్ మిన్నీ, వ లా ఖువ్వహ్',
    ),
    DuaItem(
      title: 'Kapde Utarne ki Dua',
      arabic: 'بِسْمِ اللّٰهِ',
      romanEnglish: 'Bismillaahi',
      romanTelugu: 'బిస్మిల్లాహి',
    ),
    DuaItem(
      title: 'Naye Kapde ki Dua',
      arabic:
          'اَللّٰهُمَّ لَكَ الْحَمْدُ اَنْتَ كَسَوْتَنِيْهِ اَسْئَلُكَ مِنْ خَيْرِهٖ وَخَيْرِ مَا صُنِعَ لَهٗ وَاَعُوْذُ بِكَ مِنْ شَرِّهٖ وَشَرِّ مَا صُنِعَ لَهٗ',
      romanEnglish:
          'AllaAhumma lakal hamdu anta kasawtaneehi as’aluka min khairihi wa khairi maa suni‘a lahu wa a‘oozu bika min sharrihi wa sharri maa suni‘a lahu',
      romanTelugu:
          'అల్లాహుమ్మ లకల్ హమ్దు అంత కసౌతనీహీ అస్అలుక మిన్ ఖైరిహీ వ ఖైరి మా సునిఅ లహు వ అఊజు బిక మిన్ షర్రిహీ వ షర్రి మా సునిఅ లహు',
    ),
    DuaItem(
      title: 'Aaina Dekhne ki Dua',
      arabic: 'اَللّٰهُمَّ اَنْتَ حَسَّنْتَ خَلْقِىْ فَحَسِّنْ خُلُقِىْ',
      romanEnglish: 'Allaahumma anta hassanta khalqee fahassin khuluqee',
      romanTelugu: 'అల్లాహుమ్మ అంత హస్సంత ఖల్కీ ఫ హస్సిన్ ఖులుఖీ',
    ),
    DuaItem(
      title: 'Barkat ki Dua',
      arabic: 'اَللّٰهُمَّ بَارِكْ لَنَا فِيْهِ',
      romanEnglish: 'Allaahumma baarik lanaa feehi',
      romanTelugu: 'అల్లాహుమ్మ బారిక్ లనా ఫీహి',
    ),
    DuaItem(
      title: 'Chheenk (Sneezing) ki Dua',
      arabic: 'اَلْحَمْدُ لِلّٰهِ',
      romanEnglish: 'Alhamdu lillaah',
      romanTelugu: 'అల్‌హమ్దు లిల్లాహ్',
    ),
    DuaItem(
      title: 'Chheenk ka Jawab ki Dua',
      arabic: 'يَرْحَمُكَ اللّٰهُ',
      romanEnglish: 'Yarhamukallaah',
      romanTelugu: 'యర్‌హముకల్లాహ్',
    ),
    DuaItem(
      title: 'Jamhai (Yawn) Control karne ki Dua',
      arabic: 'اَعُوْذُ بِاللّٰهِ مِنَ الشَّيْطَانِ الرَّجِيْمِ',
      romanEnglish: 'A‘oozu billaahi minash shaitaanir rajeem',
      romanTelugu: 'అఊజు బిల్లాహి మినష్ షైతానిర్ రజీమ్',
    ),

    DuaItem(
      title: 'Mushkil waqt ki Dua',
      arabic:
          'حَسْبُنَا اللّٰهُ وَنِعْمَ الْوَكِيْلُ (or) لَاۤ اِلٰهَ اِلَّاۤ اَنْتَ سُبْحٰنَكَ اِنِّىْ كُنْتُ مِنَ الظّٰلِمِيْنَ',
      romanEnglish:
          'Hasbunallaahu wa ni‘mal wakeel (or)  Laa ilaaha illaa anta subhaanaka inni kuntu minaz zaalimeen',
      romanTelugu:
          'హస్బునల్లాహు వ నిఅ్మల్ వకీల్ (or)  లా ఇలాహ ఇల్లా అంత సుభ్హానక ఇన్నీ కుంతు మినజ్ జాలిమీన్',
    ),
    DuaItem(
      title: 'Nazar (Buri Nazar) Se Bachne Ki Dua',
      arabic: 'اَعُوْذُ بِكَلِمَاتِ اللّٰهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',

      romanEnglish:
          'A‘oozu bi kalimaatillaahit taammaati min sharri maa khalaq',
      romanTelugu: 'అఊజు బి కలిమాతిల్లాహిత్ తామ్మాతి మిన్ షర్రి మా ఖలఖ్',

      arabicFontFamily: 'MuhammadiQuranic',
    ),
    DuaItem(
      title: 'Janaza Namaz ki Dua',
      arabic:
          'اَللّٰهُمَّ اغْفِرْ لِحَيِّنَا وَمَيِّتِنَا وَشَاهِدِنَا وَغَائِبِنَا وَصَغِيْرِنَا وَكَبِيْرِنَا وَذَكَرِنَا وَاُنْثَانَا\n اَللّٰهُمَّ مَنْ اَحْيَيْتَهٗ مِنَّا فَاَحْيِهٖ عَلَى الْاِسْلَامِ وَمَنْ تَوَفَّيْتَهٗ مِنَّا فَتَوَفَّهٗ عَلَى الْاِيْمَانِ',

      romanEnglish:
          'Allaahummagh-fir-li hayyinaa wa mayyitinaa wa shaahidinaa wa ghaa’ibinaa wa sageerinaa wa kabeerinaa wa zakarinaa wa unsaanaa\nAllaahumma man ah-yai-tahu minnaa fa ah-yihi ‘alal Islaam wa man tawaffaitahu minnaa fatawaffahu ‘alal eemaan',
      romanTelugu:
          "అల్లాహుమ్మగ్-ఫిర్-లి హయ్యినా వ మయ్యితినా వ షాహిదినా వ ఘాఇబినా వ సఘీరినా వ కబీరినా వ ఝకరినా వ ఉన్-సానా\nఅల్లాహుమ్మ మన్ అహ్-యై-తహు మిన్నా ఫ  ఫ అహ్-యిహి అలల్ ఇస్లామ్ వ మన్ తవఫ్ఫైతహు మిన్నా ఫతవఫ్ఫహు అలల్ ఈమాన్",
    ),
    DuaItem(
      title: 'Na-Baalig ladke ki janaze ki Dua',
      arabic:
          'اَللّٰهُمَّ اجْعَلْهُ لَنَا فَرَطًا وَّاجْعَلْهُ لَنَا اَجْرًا وَّذُخْرًا وَّاجْعَلْهُ لَنَا شَافِعًا وَّمُشَفَّعًا',
      romanEnglish:
          "Allaahummaj ‘alhu lanaa faratau waj ‘alhu lanaa ajrau wa zukhrau waj ‘alhu lanaa shaafi‘au wa mushaffa‘an",
      romanTelugu:
          'అల్లాహుమ్మజ్ అల్‌హు లనా ఫరతవ్,    వజ్ అల్‌హు లనా అజ్-రౌవ్  వ జుఖ్-రౌవ్  వజ్ అల్‌హు లనా షాఫి-అవ్   వ ముషఫ్ఫఅ',
    ),
    DuaItem(
      title: 'Na-Baalig ladki ki janaze ki Dua',
      arabic:
          'اَللّٰهُمَّ اجْعَلْهَا لَنَا فَرَطًا وَّاجْعَلْهَا لَنَا اَجْرًا وَّذُخْرًا وَّاجْعَلْهَا لَنَا شَافِعَةً وَّمُشَفَّعَةً',
      romanEnglish:
          "Allaahummaj ‘alhaa lanaa faratau waj ‘alhaa lanaa ajrau wa zukhrau waj ‘alhaa lanaa shaafi‘atau wa mushaffa‘atan",
      romanTelugu:
          'అల్లాహుమ్మజ్ అల్‌హా లనా ఫరతవ్,    వజ్ అల్‌హా లనా అజ్-రౌవ్  వ జుఖ్-రౌవ్  వజ్ అల్‌హా లనా షాఫిఆథౌవ్ వ ముషఫ్ఫఅన్',
    ),
    DuaItem(
      title: 'Itekaf ki Dua',
      arabic:
          'بِسْمِ اللّٰهِ دَخَلْتُ وَعَلَيْهِ تَوَكَّلْتُ وَنَوَيْتُ سُنَّتَ الْاِعْتِكَافِ',
      romanEnglish:
          "Bismillaahi dakhaltu wa ‘alaihi tawakkaltu wa nawaitu sunnatal i‘tekaaf",
      romanTelugu:
          'బిస్మిల్లాహి దఖల్-తు  వ అలైహి తవక్కల్-తు వ నవైతు సున్నతల్ ఎ‘తికాఫ్',
    ),
    DuaItem(
      title: 'Sehar ki Dua',
      arabic:
          'نَوَيْتُ أَنْ أَصُومَ غَدًا لِلّٰهِ تَعَالَى مِنْ صَوْمِ رَمَضَانَ',
      romanEnglish:
          "Nawaitu an a suuma ghadan lillaahi ta'ala min soumi Ramazaan.",
      romanTelugu: 'నవైతు అన్ అసూమ ఘదన్ లిల్లాహి తఆలా మిన్ సౌమి రమజాన్',
    ),
    DuaItem(
      title: 'Iftar Dua',
      arabic:
          'اَللّٰهُمَّ اِنِّىْ لَكَ صُمْتُ وَبِكَ اٰمَنْتُ وَعَلَيْكَ تَوَكَّلْتُ وَعَلٰى رِزْقِكَ اَفْطَرْتُ',
      romanEnglish:
          "Allaahumma inni laka sumtu wa bika aamantu wa ‘alaika tawakkaltu wa ‘alaa rizqika aftartu",
      romanTelugu:
          'అల్లాహుమ్మ ఇన్నీ లక సుమ్తు వ బిక ఆమంతు వ అలైక తవక్కల్తు వ అలా రిజ్ఖిక అఫ్తర్-తు',
    ),
    DuaItem(
      title: 'Gussa aaye to ye Dua padhe',
      arabic: 'أَعُوذُ بِاللّٰهِ مِنَ الشَّيْطَانِ الرَّجِيمِ',
      romanEnglish: "A'uoozu billaahi minash shaitaanir rajeem",
      romanTelugu: 'అఊజు బిల్లాహి మినష్ షైతానిర్ రజీమ్',
    ),
    DuaItem(
      title: 'Sana',
      arabic:
          'سُبْحَانَكَ اللَّهُمَّ وَبِحَمْدِكَ وَتَبَارَكَ اسْمُكَ وَتَعَالَىٰ جَدُّكَ وَلَا إِلَٰهَ غَيْرُكَ',
      romanEnglish:
          "Sub-haanaka Allahumma wabiham-dika wa tabaarakasmuka wa ta'ala jadduka wa laa ilaaha ghairuk",
      romanTelugu:
          'సుబ్-హనక అల్లహుమ్మ వబిహందిక వతబారకస్ముక వ తఆలా జద్దుక వ లా ఇలాహ ఘైరుక్',
    ),
    DuaItem(
      title: 'Tashahhud',
      arabic:
          'التَّحِيَّاتُ لِلَّهِ وَالصَّلَوَاتُ وَالطَّيِّبَاتُ\nالسَّلَامُ عَلَيْكَ أَيُّهَا النَّبِيُّ وَرَحْمَةُ اللَّهِ وَبَرَكَاتُهُ\nالسَّلَامُ عَلَيْنَا وَعَلَىٰ عِبَادِ اللَّهِ الصَّالِحِينَ\nأَشْهَدُ أَنْ لَا إِلَٰهَ إِلَّا اللَّهُ وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ',
      romanEnglish:
          "Atta-hiyyaatu lillaahi was-swala-waatu wattayyi-baatu, assalaamu 'alaika ayyuhan-nabiyyu wa rahmatullaahi wa barakaatuhu, assalaamu 'alainaa wa 'alaa ibaadillaahis-swaali-heen. Ash-hadu allaa ilaaha illal-laahu wa ash-hadu anna Muhammadan 'abduhuu wa rasooluhu",
      romanTelugu:
          'అత్తహియ్యాతు లిల్లాహి వాస్ స్వలవాతు వత్తయ్యిబాతు। అస్సలాము అలైక అయ్యుహన్నబియ్యు వ రహ్మతుల్లాహి వ బరకాతుహు। అస్సలాము అలైనా వ అలా ఇబాదిల్లా హిస్ స్వలిహీన్। అష్-హదు అల్లా ఇలాహ ఇల్లల్లాహు వ అష్-హదు అన్న ముహమ్మదన్ అబ్దుహూ వ రసూలుహు।',
    ),
    DuaItem(
      title: 'Durood-e-Ibrahim',
      arabic:
          'اللَّهُمَّ صَلِّ عَلَىٰ مُحَمَّدٍ وَعَلَىٰ آلِ مُحَمَّدٍ\nكَمَا صَلَّيْتَ عَلَىٰ إِبْرَاهِيمَ وَعَلَىٰ آلِ إِبْرَاهِيمَ إِنَّكَ حَمِيدٌ مَجِيدٌ\nاللَّهُمَّ بَارِكْ عَلَىٰ مُحَمَّدٍ وَعَلَىٰ آلِ مُحَمَّدٍ\nكَمَا بَارَكْتَ عَلَىٰ إِبْرَاهِيمَ وَعَلَىٰ آلِ إِبْرَاهِيمَ إِنَّكَ حَمِيدٌ مَجِيدٌ',
      romanEnglish:
          "Allaahumma swalli 'alaa Muhammadiv wa 'alaa aali Muhammadin kamaa swallaita 'alaa Ibraaheema wa 'alaa aali Ibraaheema innaka Hameedum Majeed. Allaa-humma baarik 'alaa Muhammadiv wa 'alaa aali Muhammadin kamaa baa-rakta 'alaa Ibraaheema wa 'alaa aali Ibraaheema innaka Hameedum Majeed.",
      romanTelugu:
          'అల్లాహుమ్మ స్వల్లీ అలా ముహమ్మదివ్ వ అలా ఆలి ముహమ్మదిన్ కమా స్వల్లైత అలా ఇబ్రాహీమ వ అలా ఆలి ఇబ్రాహీమ ఇన్నక హమీదుమ్ మజీద్। అల్లాహుమ్మ బారిక్ అలా ముహమ్మదివ్ వ అలా ఆలి ముహమ్మదిన్ కమా బారక్త అలా ఇబ్రాహీమ వ అలా ఆలి ఇబ్రాహీమ ఇన్నక హమీదుమ్ మజీద్।',
    ),
    DuaItem(
      title: 'Dua-e-Masoora',
      arabic:
          'اللَّهُمَّ إِنِّي ظَلَمْتُ نَفْسِي ظُلْمًا كَثِيرًا وَلَا يَغْفِرُ الذُّنُوبَ إِلَّا أَنْتَ فَاغْفِرْ لِي مَغْفِرَةً مِنْ عِنْدِكَ وَارْحَمْنِي إِنَّكَ أَنْتَ الْغَفُورُ الرَّحِيمُ',
      romanEnglish:
          "Allaa-humma inni zalamtu naf-sii zul-man kaseerau, walaa yag-firuz-zunooba illaa anta, faghfir lee maghfiratam min 'indika warhamnii, innaka antal Ghafoorur Raheem.",
      romanTelugu:
          'అల్లాహుమ్మ ఇన్నీ జలంతు నఫ్సీ జుల్-మన్ కసీరౌ, వలా యఘ్ఫిరుజ్ జునూబ ఇల్లా అంత, ఫఘ్ఫిర్లీ మగ్ఫిరతం మిన్ ఇందిక వర్హమ్నీ, ఇన్నక అంతల్ ఘఫూరుర్ రహీమ్।',
    ),
    DuaItem(
      title: 'Dua e qunooth',
      arabic:
          'اللّٰهُمَّ إِنَّا نَسْتَعِينُكَ وَنَسْتَغْفِرُكَ وَنُؤْمِنُ بِكَ وَنَتَوَكَّلُ عَلَيْكَ وَنُثْنِي عَلَيْكَ الْخَيْرَ وَنَشْكُرُكَ وَلَا نَكْفُرُكَ وَنَخْلَعُ وَنَتْرُكُ مَنْ يَفْجُرُكَ۔\n\nاللّٰهُمَّ إِيَّاكَ نَعْبُدُ وَلَكَ نُصَلِّي وَنَسْجُدُ وَإِلَيْكَ نَسْعَى وَنَحْفِدُ وَنَرْجُو رَحْمَتَكَ وَنَخْشَى عَذَابَكَ إِنَّ عَذَابَكَ بِالْكُفَّارِ مُلْحِقٌ۔',
      romanEnglish:
          "Allaa-humma innaa nasta'eenuka wa nastag-firuka wa nu'minu bika wa nata-wakkalu 'alaiyka wa nusnii 'alaiykal khair wa nashkuruka wa laa nakfuruka wa nakhla'u wa nathruku mai yaf-juruka. Allaa-humma iyyaka na'budu wa laka nu-swalli wa nasjudu wa ilaika nas'aa wa nah-fidu wa-narjuu rahmataka wa nakh-shaa 'azaa-baka inna 'azaa-baka bil-kuffaari mulhiq.",
      romanTelugu:
          'అల్లాహుమ్మ ఇన్నా నస్తఈనుక వనస్-తగ్-ఫిరుక వ నుఅ్‌-మిను బిక వన-తవక్కలు అలైక వ నుస్-నీ అలైకల్ ఖైర వ నష్-కురుక వలా నక్-ఫురుక వ నఖ్-లఊ వ నత్-రుకు మయ్యఫ్‌జురుక। అల్లాహుమ్మ ఇయ్యాక నఅ్‌బుదు వ లక నుసల్లీ వ నస్-జుదు వ ఇలైక నస్అా వ నహ్-ఫిదు వ నర్జూ రహ్-మతక వ నఖ్-షా అజా-బక ఇన్న అజా-బక బిల్ కుఫ్ఫారి ముల్-హిఖ్.',
    ),
    DuaItem(
      title: 'Istikhara ki Dua',
      arabic:
          'اَللّٰهُمَّ اِنِّىْ اَسْتَخِيْرُكَ بِعِلْمِكَ وَاَسْتَقْدِرُكَ بِقُدْرَتِكَ وَاَسْئَلُكَ مِنْ فَضْلِكَ الْعَظِيْمِ فَاِنَّكَ تَقْدِرُ وَلَاۤ اَقْدِرُ وَتَعْلَمُ وَلَاۤ اَعْلَمُ وَاَنْتَ عَلَّامُ الْغُيُوْبِ\nاَللّٰهُمَّ اِنْ كُنْتَ تَعْلَمُ اَنَّ هٰذَا الْاَمْرَ خَيْرٌ لِّىْ فِىْ دِيْنِىْ وَمَعَاشِىْ وَعَاقِبَةِ اَمْرِىْ فَاقْدُرْهُ لِىْ وَيَسِّرْهُ لِىْ ثُمَّ بَارِكْ لِىْ فِيْهِ\nوَاِنْ كُنْتَ تَعْلَمُ اَنَّ هٰذَا الْاَمْرَ شَرٌّ لِّىْ فِىْ دِيْنِىْ وَمَعَاشِىْ وَعَاقِبَةِ اَمْرِىْ فَاصْرِفْهُ عَنِّىْ وَاصْرِفْنِىْ عَنْهُ وَاقْدُرْ لِىَ الْخَيْرَ حَيْثُ كَانَ ثُمَّ اَرْضِنِىْ بِهٖ',

      romanEnglish:
          "Allaahumma innee astakheeruka bi‘ilmika wa astaqdiruka biqudratika wa as’aluka min fazlikal ‘azeem fa innaka taqdiru wa laa aqdiru wa ta‘lamu wa laa a‘lamu wa anta ‘allaamul ghuyoob.  Allaahumma in kuntha ta‘lamu anna haazal amra khairul lee fee deenee wa ma‘aashee wa ‘aaqibathi amree faqdurhu lee wa yassirhu lee summa baarik lee feehi.  Wa in kuntha ta‘lamu anna haazal amra sharrul lee fee deenee wa ma‘aashee wa ‘aaqibathi amree fasrifhu ‘annee wasrifnee ‘anhu waqdur liyal khaira haisu kaana summa arzinee bihi",
      romanTelugu:
          'అల్లాహుమ్మ ఇన్నీ అస్-తఖీరుక బి ఇల్మిక వ అస్-తఖ్-దిరుక  బిఖుద్రతిక వ అస్అలుక మిన్ ఫజ్లికల్ అజీమ్. ఫ ఇన్నక తఖ్-దిరు వ లా అఖ్-దిరు.  వ త‘లము వ లా అ‘లము వ అంత అల్లాముల్ ఘుయూబ్.  అల్లాహుమ్మ ఇన్ కుంత త‘లము అన్న హాజల్ అమ్ర ఖైరుల్ లీ ఫీ దీనీ వ మా ఆషీ వ ఆఖిబతి అమ్రీ ఫఖ్-దుర్-హు లీ వ యస్సిర్-హు లీ సుమ్మ బారిక్ లీ ఫీహి. వ ఇన్ కుంత త‘లము అన్న హాజల్ అమ్ర షర్రుల్ లీ ఫీ దీనీ వ మా ఆషీ వ ఆఖిబతి అమ్రీ ఫస్-రిఫ్-హు అన్నీ వస్-రిఫ్-నీ అన్-హు వఖ్-దుర్ లియల్ ఖైర హైసు కాన సుమ్మ అర్-జినీ బిహి',
    ),
    DuaItem(
      title: 'Musibat zada ko dekhthe vaqt ki Dua',
      arabic:
          'اَلْحَمْدُ لِلّٰهِ الَّذِىْ عَافَانِىْ مِمَّا ابْتَلَاكَ بِهٖ وَفَضَّلَنِىْ عَلٰى كَثِيْرٍ مِّمَّنْ خَلَقَ تَفْضِيْلًا',
      romanEnglish:
          "Alhamdu lillaahil lazee ‘aafaanee mimmaab talaaka bihee wa fazzalanee ‘alaa kaseerim mimman khalaqa tafzeelaa",
      romanTelugu:
          'అల్హమ్దు లిల్లాహిల్లజీ ఆఫానీ మిమ్మాబ్-తలాక  బిహీ వ ఫజ్జలనీ అలా కసీరిమ్ మిమ్మన్ ఖలఖ తఫ్జీలా',
    ),
    DuaItem(
      title: 'Sawari par sawar hone lago to ye Dua padhe',
      arabic:
          'سُبْحٰنَ الَّذِىْ سَخَّرَ لَنَا هٰذَا وَمَا كُنَّا لَهٗ مُقْرِنِيْنَ وَاِنَّاۤ اِلٰى رَبِّنَا لَمُنْقَلِبُوْنَ',
      romanEnglish:
          'Subhaanallazee saqqara lanaa haazaa wa maa kunnaa lahuu muqrineen, wa innaa ilaa Rabbinaa lamunqaliboon',
      romanTelugu:
          'సుబ్-హా-నల్లజీ సఖ్ఖర లనా హాజా వ మా కున్నా లహూ ముఖ్-రినీన్, వ ఇన్నా ఇలా రబ్బినా లమున్-ఖలిబూన్',
    ),
    DuaItem(
      title: 'Dua for Wedding / Marriage Night',
      arabic:
          'اَللّٰهُمَّ اِنِّىْ اَسْئَلُكَ خَيْرَهَا وَخَيْرَ مَا جَبَلْتَهَا عَلَيْهِ وَأَعُوْذُ بِكَ مِنْ شَرِّهَا وَشَرِّ مَا جَبَلْتَهَا عَلَيْهِ',
      romanEnglish:
          'Allahumma inni as’aluka khairahaa wa khaira maa jabaltahaa ‘alaihi wa a‘oozu bika min sharrihaa wa sharri maa jabaltahaa ‘alaihi',
      romanTelugu:
          'అల్లాహుమ్మ ఇన్నీ అస్అలుక ఖైరహా వ ఖైర మా జబల్తహా అలైహి వ అఊజు బిక మిన్ షర్రిహా వ షర్రి మా జబల్తహా అలైహి',
    ),
    DuaItem(
      title: 'Hum Bistari Ki Dua',
      arabic:
          'بِسْمِ اللّٰهِ اَللّٰهُمَّ جَنِّبْنَا الشَّيْطٰنَ وَجَنِّبِ الشَّيْطٰنَ مَا رَزَقْتَنَا',
      romanEnglish:
          'Bismillaahi Allaahumma jannibnash shaitaana wa jannibish shaitaana maa razaqtanaa',
      romanTelugu:
          'బిస్మిల్లాహి అల్లాహుమ్మ జన్నిబ్-నష్  షైతాన వ జన్నిబిష్ షైతాన మా రజఖ్-తనా',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Masnoon Dua'), centerTitle: true),
      body: _duas.isEmpty
          ? const _EmptyDuaState()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _duas.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.35)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 18,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'The Roman English and Telugu transliterations may differ in pronunciation. For correct pronunciations, contact ulamas.',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final item = _duas[index - 1];
                return _DuaTile(
                  number: index,
                  title: item.title,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DuaDetailScreen(dua: item),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _DuaTile extends StatelessWidget {
  const _DuaTile({
    required this.number,
    required this.title,
    required this.onTap,
  });

  final int number;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFFB65C1D).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFB65C1D).withOpacity(0.25),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  number.toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB65C1D),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.menu_book_rounded, color: Color(0xFFB65C1D)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDuaState extends StatelessWidget {
  const _EmptyDuaState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No duas added yet.\nAdd items to the list in DuaScreen.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey),
        ),
      ),
    );
  }
}

class _DuaFooter extends StatelessWidget {
  const _DuaFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: Text(
          'More duas will be coming soon',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ),
    );
  }
}
