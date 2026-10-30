/// Reasons a drop or a comment can be reported for (DSA Art. 16), as [English, Finnish].
/// Keys match the API's REPORT_REASONS.
const reportReasons = {
  'ILLEGAL_PRODUCT': ['Illegal or dangerous product', 'Laiton tai vaarallinen tuote'],
  'COUNTERFEIT': ['Counterfeit or fake brand', 'Väärennös'],
  'SCAM': ['Scam or misleading', 'Huijaus tai harhaanjohtava'],
  'NUDITY': ['Nudity or sexual content', 'Alastomuus tai seksuaalinen sisältö'],
  'VIOLENCE': ['Violence', 'Väkivalta'],
  'HATE': ['Hate speech', 'Vihapuhe'],
  'HARASSMENT': ['Harassment', 'Häirintä'],
  // Copyright and trademark notices ask for the DSA Art. 16(2) details (widgets/ip_notice_form.dart, API 2.16)
  'COPYRIGHT': ['Copyright: uses my work', 'Tekijänoikeus: käyttää teostani'],
  'TRADEMARK': ['Trademark: uses my brand', 'Tavaramerkki: käyttää tavaramerkkiäni'],
  'MINOR_SAFETY': ['Child safety', 'Lasten turvallisuus'],
  'OTHER': ['Something else', 'Jokin muu'],
};
