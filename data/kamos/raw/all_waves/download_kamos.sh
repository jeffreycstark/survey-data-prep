#!/bin/bash
# Download all KAMOS SPSS data files + Interview Survey questionnaires from caporci.org
# Filenames include start/end dates from the website
# Skips: Excel files, Online Survey questionnaires

BASE="http://caporci.org/eng/ezs_board/ezsboard_filedownload.php"
DIR="$(dirname "$0")"

echo "=== Downloading KAMOS SPSS Data Files ==="

# --- KAMOS 1-1: Feb-May 2016 (Interview Survey) ---
echo "Downloading KAMOS 1-1 SPSS (2016.02.16-2016.05.16)..."
curl -k -s -L -o "$DIR/KAMOS_1-1_2016.02.16-2016.05.16_data.sav" \
  "${BASE}?nfile=1_1571298316.sav&ofile=KAMOS+1-1+data+e.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=14"

echo "Downloading KAMOS 1-1 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_1-1_2016.02.16-2016.05.16_questionnaire_interview.pdf" \
  "${BASE}?nfile=1_1490058716.pdf&ofile=2016+KMOS1%28variable+names%29_final%28pdf%29.pdf&b_path2=../../ezs_data/board/table_301&b_code=301&idx=11"

# --- KAMOS 1-2: Jun-Aug 2016 (Online Survey — SPSS only, skip questionnaire) ---
echo "Downloading KAMOS 1-2 SPSS (2016.06.23-2016.08.09)..."
curl -k -s -L -o "$DIR/KAMOS_1-2_2016.06.23-2016.08.09_data.sav" \
  "${BASE}?nfile=1_1571298334.sav&ofile=KAMOS+1-2+Data+e.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=16"

# --- KAMOS 2-1: Jun-Aug 2017 (Interview Survey) ---
echo "Downloading KAMOS 2-1 SPSS (2017.05.16-2017.07.10)..."
curl -k -s -L -o "$DIR/KAMOS_2-1_2017.05.16-2017.07.10_data.sav" \
  "${BASE}?nfile=1_1571298377.sav&ofile=KAMOS+2-1+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=17"

echo "Downloading KAMOS 2-1 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_2-1_2017.05.16-2017.07.10_questionnaire_interview.pdf" \
  "${BASE}?nfile=1_1505575361.pdf&ofile=KAMOS+Questionnaire+June-August+2017.pdf&b_path2=../../ezs_data/board/table_301&b_code=301&idx=20"

# --- KAMOS 2-2: Sep-Oct 2017 (Online Survey — SPSS only) ---
echo "Downloading KAMOS 2-2 SPSS (2017.08.09-2017.09.29)..."
curl -k -s -L -o "$DIR/KAMOS_2-2_2017.08.09-2017.09.29_data.sav" \
  "${BASE}?nfile=1_1571298407.sav&ofile=KAMOS+2-2+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=21"

# --- KAMOS 2-3: Mar-Apr 2018 (Online Survey — SPSS only) ---
echo "Downloading KAMOS 2-3 SPSS (2018.03.19-2018.04.16)..."
curl -k -s -L -o "$DIR/KAMOS_2-3_2018.03.19-2018.04.16_data.sav" \
  "${BASE}?nfile=1_1571298428.sav&ofile=KAMOS+2-3+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=26"

# --- KAMOS 3-1: Apr-Jun 2018 (Interview Survey) ---
echo "Downloading KAMOS 3-1 SPSS (2018.04.23-2018.06.22)..."
curl -k -s -L -o "$DIR/KAMOS_3-1_2018.04.23-2018.06.22_data.sav" \
  "${BASE}?nfile=1_1571298460.sav&ofile=KAMOS+3-1+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=29"

echo "Downloading KAMOS 3-1 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_3-1_2018.04.23-2018.06.22_questionnaire_interview.pdf" \
  "${BASE}?nfile=1_1554886682.pdf&ofile=KAMOS+questionnaire+April+-+June+2018.pdf&b_path2=../../ezs_data/board/table_301&b_code=301&idx=28"

# --- KAMOS 3-2: Oct-Nov 2018 (Online Survey — SPSS only) ---
echo "Downloading KAMOS 3-2 SPSS (2018.10.05-2018.11.04)..."
curl -k -s -L -o "$DIR/KAMOS_3-2_2018.10.05-2018.11.04_data.sav" \
  "${BASE}?nfile=1_1571298478.sav&ofile=KAMOS+3-2+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=32"

# --- KAMOS 3-3: Jan-Mar 2019 (no dates/mode specified on page) ---
echo "Downloading KAMOS 3-3 SPSS (2019.01-2019.03)..."
curl -k -s -L -o "$DIR/KAMOS_3-3_2019.01-2019.03_data.sav" \
  "${BASE}?nfile=1_1571298495.sav&ofile=KAMOS+3-3+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=35"

# --- KAMOS 4-1: Apr-Jun 2019 (Interview Survey) ---
echo "Downloading KAMOS 4-1 SPSS (2019.04.20-2019.06.20)..."
curl -k -s -L -o "$DIR/KAMOS_4-1_2019.04.20-2019.06.20_data.sav" \
  "${BASE}?nfile=1_1571298519.sav&ofile=KAMOS+4-1+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=38"

echo "Downloading KAMOS 4-1 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_4-1_2019.04.20-2019.06.20_questionnaire_interview.pdf" \
  "${BASE}?nfile=1_1564979920.pdf&ofile=KAMOS+4-1+%28E%29.pdf&b_path2=../../ezs_data/board/table_301&b_code=301&idx=37"

# --- KAMOS 4-2: Sep-Oct 2019 (Interview Survey) ---
echo "Downloading KAMOS 4-2 SPSS (2019.09.10-2019.10.04)..."
curl -k -s -L -o "$DIR/KAMOS_4-2_2019.09.10-2019.10.04_data.sav" \
  "${BASE}?nfile=1_1594259210.sav&ofile=KAMOS+4-2+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=43"

echo "Downloading KAMOS 4-2 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_4-2_2019.09.10-2019.10.04_questionnaire_interview.pdf" \
  "${BASE}?nfile=1_1570670921.pdf&ofile=2019+KAMOS2+qestionaire.pdf&b_path2=../../ezs_data/board/table_301&b_code=301&idx=44"

# --- KAMOS 4-3: Nov-Dec 2019 (no mode specified; questionnaire is .hwp) ---
echo "Downloading KAMOS 4-3 SPSS (2019.11.27-2019.12.04)..."
curl -k -s -L -o "$DIR/KAMOS_4-3_2019.11.27-2019.12.04_data.sav" \
  "${BASE}?nfile=1_1594258359.sav&ofile=KAMOS+4-3+%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=47"

# --- KAMOS 5-1: Mar-Apr 2020 (Interview Survey) corona-19 ---
echo "Downloading KAMOS 5-1 SPSS (2020.03-2020.04) corona-19..."
curl -k -s -L -o "$DIR/KAMOS_5-1_2020.03-2020.04_data_corona19.sav" \
  "${BASE}?nfile=1_1594260073.sav&ofile=KAMOS+5-1%28E%29+corona-19.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=49"

echo "Downloading KAMOS 5-1 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_5-1_2020.03-2020.04_questionnaire_interview.docx" \
  "${BASE}?nfile=1_1593412890.docx&ofile=2020+KAMOS1+qestionaire.docx&b_path2=../../ezs_data/board/table_301&b_code=301&idx=48"

# --- KAMOS 5-2: May-Jun 2020 (Interview Survey) ---
echo "Downloading KAMOS 5-2 SPSS (2020.05-2020.06)..."
curl -k -s -L -o "$DIR/KAMOS_5-2_2020.05-2020.06_data.sav" \
  "${BASE}?nfile=1_1597124527.sav&ofile=kAMOS+5-2%28E%29.sav&b_path2=../../ezs_data/board/table_301&b_code=301&idx=52"

echo "Downloading KAMOS 5-2 Questionnaire (Interview Survey)..."
curl -k -s -L -o "$DIR/KAMOS_5-2_2020.05-2020.06_questionnaire_interview.docx" \
  "${BASE}?nfile=1_1597124461.docx&ofile=2020_%ED%95%9C%EA%B5%AD%EC%82%AC%ED%9A%8C%EA%B3%BC%ED%95%99+2%EC%B0%A8%EC%98%A8%EB%9D%BC%EC%9D%B8%EC%A1%B0%EC%82%AC+%EC%84%A4%EB%AC%B8%EC%A7%80+ENG.docx&b_path2=../../ezs_data/board/table_301&b_code=301&idx=51"

echo ""
echo "=== Download complete ==="
echo "Files saved to: $DIR"
ls -lh "$DIR"/*.sav "$DIR"/*.pdf "$DIR"/*.docx 2>/dev/null
