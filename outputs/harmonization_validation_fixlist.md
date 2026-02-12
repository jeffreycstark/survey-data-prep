# Harmonization Validation Fix List

Generated from harmonization_validation_triage.csv

| spec | var_id | waves | errors | warns | top_cause | suggestion |
|---|---|---|---:|---:|---|---|
| demographics | education_level | w1,w2,w3,w4,w5,w6 | 6 | 0 | coverage_loss; missing_codes_not_na | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| demographics | int_month | w1,w2,w3,w4,w5,w6 | 6 | 0 | coverage_loss; missing_codes_not_na | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| meaning_of_democracy | dem_essential_core | w2,w3,w4,w5,w6 | 5 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| meaning_of_democracy | electoral_status | w2,w3,w4,w5,w6 | 5 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| demographics | country | w1,w2,w3,w4,w5 | 5 | 0 | coverage_loss; missing_codes_not_na | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| meaning_of_democracy | dem_procedural_vs_substantive | w2,w3,w4,w5,w6 | 5 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| meaning_of_democracy | procedural_preference_index | w2,w3,w4,w5,w6 | 5 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| demographics | seeking_employment | w3,w4,w5,w6 | 4 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| globalization | glob_cultural_defense | w1,w2,w3,w4 | 4 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| governance | problem_most_important | w3,w4,w5,w6 | 4 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| public_services | access_police | w2,w3,w4,w5 | 4 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| democracy | dem_vs_equality | w3,w4,w5,w6 | 4 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| clientelism | social_support_available | w3,w4,w5 | 3 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| globalization | glob_trade_protection | w2,w3,w4 | 3 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_development_model | w3,w4,w5 | 3 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_action | vote_buying_offered | w3,w4,w6 | 3 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| public_services | access_healthcare | w2,w3,w4 | 3 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| clientelism | community_leader_contact | w3,w5,w6 | 3 | 0 | coverage_loss; missing_codes_not_na | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| social_trust | trust_acquaintances | w2,w3,w5 | 3 | 0 | transform_mismatch_or_data_anomaly; one_to_many_mapping | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| social_trust | trust_neighbors | w2,w3,w5 | 3 | 0 | transform_mismatch_or_data_anomaly; one_to_many_mapping | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| social_trust | trust_relatives | w2,w3,w5 | 3 | 0 | transform_mismatch_or_data_anomaly; one_to_many_mapping | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| demographics | education_years | w2,w3,w4,w5,w6 | 2 | 3 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_action | voted_last_election | w3,w5,w6 | 2 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| social_trust | trust_generalized_binary | w1,w3,w5 | 2 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| demographics | religion | w5,w6 | 2 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| institutional_trust | trust_election_commission | w5,w6 | 2 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| institutional_trust | trust_ngos | w5,w6 | 2 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_future_influence_asia | w3,w4,w5 | 1 | 2 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_most_influence_asia | w3,w4,w5 | 1 | 2 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_action | voted_winning_losing | w5,w6 | 1 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| demographics | current_status_unemployed | w3 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| demographics | religiosity_practice | w3 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| demographics | religiosity_self | w3 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| governance | gov_economic_equality | w1 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| governance | gov_free_to_organize | w1 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_china_country_influence_valence_w4 | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_china_world_influence | w5 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_follow_foreign_events | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_usa_country_influence_valence_w4 | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_usa_world_influence | w5 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_action | action_internet_political | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_action | voting_frequency | w3 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_attitudes | pol_news_newspaper | w1 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_attitudes | pol_news_radio | w1 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_attitudes | pol_news_television | w1 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| public_services | access_identity_document | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| public_services | access_public_school | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| social_media | internet_political_info | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| social_media | sm_express_political | w4 | 1 | 0 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| corruption | corrupt_local_govt | w6 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| corruption | corrupt_national_govt | w6 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| democracy_satisfaction | hh_income_sat | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| economic_attitudes | econ_family_income_fair | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_civil_service | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_courts | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_local_government | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_military | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_national_government | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_newspapers | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_parliament | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_police | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_political_parties | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_president | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| institutional_trust | trust_television | w5 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| political_attitudes | pol_discuss | w1 | 1 | 0 | transform_mismatch_or_data_anomaly | Check wave-specific method and raw labels; consider identity vs reverse or scale conversion. |
| demographics | int_year | w3 | 1 | 0 | raw_out_of_range_or_missing_codes; transform_mismatch_or_data_anomaly | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| social_trust | trust_strangers | w5 | 1 | 0 | monotonic_scale_mismatch | Verify scale conversion (e.g., 5→4, 6→4) for the wave. |
| demographics | idnumber | w1,w2,w3,w4,w5,w6 | 0 | 6 | range_spec_mismatch | Verify YAML valid_range and wave-specific ranges. |
| demographics | age | w3,w5,w6 | 0 | 3 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_attitudes | govt_withholds_info | w5,w6 | 0 | 2 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| governance | gov_elections_real_choice | w5 | 0 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| international_relations | intl_close_to_asean | w6 | 0 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| meaning_of_democracy | dem_meaning_set4 | w6 | 0 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| political_attitudes | citizen_loyalty_country | w2 | 0 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| public_services | access_internet | w5 | 0 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |
| public_services | access_transport | w5 | 0 | 1 | raw_out_of_range_or_missing_codes | Inspect raw codes; expand missing_conventions or adjust valid_range by wave. |